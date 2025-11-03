# main.py
import os
import secrets
import httpx
import logging
from datetime import datetime, timedelta
from typing import Dict

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session
from dotenv import load_dotenv

import models
from database import engine, get_db

logger = logging.getLogger("uvicorn")
load_dotenv()

CLIENT_ID = os.getenv("CLIENT_ID")
CLIENT_SECRET = os.getenv("CLIENT_SECRET")
if not CLIENT_ID or not CLIENT_SECRET:
    raise ValueError("CLIENT_ID и CLIENT_SECRET должны быть установлены в .env файле")

models.Base.metadata.create_all(bind=engine)
app = FastAPI()

BANK_TOKEN_CACHE: Dict[str, Dict] = {}

BANK_CONFIGS = {
    "vbank": {"client_id": CLIENT_ID, "client_secret": CLIENT_SECRET, "base_url": "https://vbank.open.bankingapi.ru", "auto_approve": True},
    "abank": {"client_id": CLIENT_ID, "client_secret": CLIENT_SECRET, "base_url": "https://abank.open.bankingapi.ru", "auto_approve": True},
    "sbank": {"client_id": CLIENT_ID, "client_secret": CLIENT_SECRET, "base_url": "https://sbank.open.bankingapi.ru", "auto_approve": False}
}

# ... (вспомогательные функции log_request, log_response, get_bank_token, fetch_accounts остаются без изменений) ...
def log_request(request: httpx.Request): logger.info(f"--> {request.method} {request.url}\n    Headers: {request.headers}\n    Body: {request.content.decode() if request.content else ''}")
def log_response(response: httpx.Response): logger.info(f"<-- {response.status_code} URL: {response.url}\n    Response JSON: {response.text}")
async def get_bank_token(bank_name: str) -> str:
    # ... без изменений ...
    cache_entry = BANK_TOKEN_CACHE.get(bank_name)
    if cache_entry and cache_entry["expires_at"] > datetime.utcnow(): return cache_entry["token"]
    config = BANK_CONFIGS[bank_name]
    token_url = f"{config['base_url']}/auth/bank-token"
    params = {"client_id": config['client_id'], "client_secret": config['client_secret']}
    async with httpx.AsyncClient() as client:
        response = await client.post(token_url, params=params)
    if response.status_code != 200: raise HTTPException(status_code=500, detail=f"Failed to get bank token: {response.text}")
    token_data = response.json()
    BANK_TOKEN_CACHE[bank_name] = {"token": token_data['access_token'], "expires_at": datetime.utcnow() + timedelta(seconds=token_data['expires_in'] - 60)}
    return token_data['access_token']
async def fetch_accounts(bank_access_token: str, consent_id: str, bank_client_id: str, bank_name: str) -> dict:
    # ... без изменений ...
    config = BANK_CONFIGS[bank_name]
    accounts_url = f"{config['base_url']}/accounts"
    headers = {"Authorization": f"Bearer {bank_access_token}", "X-Requesting-Bank": config['client_id'], "X-Consent-Id": consent_id}
    params = {"client_id": bank_client_id}
    async with httpx.AsyncClient() as client:
        response = await client.get(accounts_url, headers=headers, params=params)
    if response.status_code != 200: raise HTTPException(status_code=500, detail=f"Failed to fetch accounts: {response.text}")
    return response.json()

@app.get("/connection/check/{bank_name}/{client_suffix}", summary="Шаг 0: Проверить наличие подключения в БД")
async def check_connection_exists(bank_name: str, client_suffix: int, db: Session = Depends(get_db)):
    """
    Проверяет, существует ли уже запись о подключении для данного банка и клиента,
    не создавая нового подключения.
    """
    user_id = 1 # Наш тестовый пользователь
    full_bank_client_id = f"{CLIENT_ID}-{client_suffix}"

    logger.info(f"Проверка наличия подключения для клиента {full_bank_client_id} в банке {bank_name}...")

    connection = db.query(models.ConnectedBank).filter(
        models.ConnectedBank.user_id == user_id,
        models.ConnectedBank.bank_name == bank_name,
        models.ConnectedBank.bank_client_id == full_bank_client_id
    ).first()

    if connection:
        logger.info(f"Подключение найдено. ID: {connection.id}, Статус: {connection.status}")
        return {
            "status": "exists",
            "message": "A connection for this client already exists.",
            "connection_id": connection.id,
            "connection_status": connection.status
        }
    else:
        logger.info("Подключение не найдено.")
        raise HTTPException(
            status_code=404,
            detail="Connection not found for the specified bank and client."
        )

@app.post("/connect/{bank_name}/{client_suffix}", summary="Шаг 1: Инициировать подключение")
async def initiate_connection(bank_name: str, client_suffix: int, db: Session = Depends(get_db)):
    config = BANK_CONFIGS[bank_name]
    user_id = 1
    full_bank_client_id = f"{config['client_id']}-{client_suffix}"

    # --- ИЗМЕНЕНИЕ: Проверяем, существует ли уже такое подключение, ВКЛЮЧАЯ ИМЯ БАНКА ---
    existing_connection = db.query(models.ConnectedBank).filter(
        models.ConnectedBank.user_id == user_id,
        models.ConnectedBank.bank_client_id == full_bank_client_id,
        models.ConnectedBank.bank_name == bank_name # <-- ПРОВЕРКА ДОБАВЛЕНА ЗДЕСЬ
    ).first()

    if existing_connection:
        logger.info(f"Подключение для клиента {full_bank_client_id} в банке {bank_name} уже существует (ID: {existing_connection.id}).")
        return {
            "status": "already_initiated",
            "message": "Connection has been already initiated. To refresh data or check status, use the /check_consent endpoint.",
            "connection_id": existing_connection.id
        }

    # --- Если подключения нет, создаем новое ---
    bank_access_token = await get_bank_token(bank_name)
    consent_url = f"{config['base_url']}/account-consents/request"
    headers = {"Authorization": f"Bearer {bank_access_token}", "Content-Type": "application/json", "X-Requesting-Bank": config['client_id']}
    consent_body = {"client_id": full_bank_client_id, "permissions": ["ReadAccountsDetail", "ReadBalances", "ReadTransactionsDetail"], "reason": f"Агрегация счетов для {full_bank_client_id}", "requesting_bank": "FinApp"}
    
    async with httpx.AsyncClient() as client:
        response = await client.post(consent_url, headers=headers, json=consent_body)
    log_response(response)
        
    if response.status_code != 200: raise HTTPException(status_code=500, detail=f"Failed to create consent request: {response.text}")
    consent_data = response.json()

    if consent_data.get("auto_approved"):
        consent_id = consent_data['consent_id']
        connection = models.ConnectedBank(user_id=user_id, bank_name=bank_name, bank_client_id=full_bank_client_id, consent_id=consent_id, status="active")
        db.add(connection)
        db.commit()
        return {"status": "success_auto_approved", "message": "Connection created and auto-approved.", "connection_id": connection.id}
    else:
        request_id = consent_data['request_id']
        # ИЗМЕНЕНИЕ: Устанавливаем новый статус при создании
        connection = models.ConnectedBank(user_id=user_id, bank_name=bank_name, bank_client_id=full_bank_client_id, request_id=request_id, status="awaitingauthorization")
        db.add(connection)
        db.commit()
        # ИЗМЕНЕНИЕ: Возвращаем новый статус
        return {"status": "awaiting_authorization", "message": "Connection initiated. Please approve and check status.", "connection_id": connection.id}


@app.post("/check_consent/{connection_id}", summary="Шаг 2: Проверить статус или обновить данные")
async def check_consent_status(connection_id: int, db: Session = Depends(get_db)):
    connection = db.query(models.ConnectedBank).filter(models.ConnectedBank.id == connection_id).first()
    if not connection: raise HTTPException(status_code=404, detail="Connection not found")
    
    # ИЗМЕНЕНИЕ: Проверяем, что статус не является финальным (например, 'active' или 'rejected')
    if connection.status not in ["awaitingauthorization", "active"]:
         return {"status": connection.status, "message": f"Consent is in a final state: {connection.status}"}

    config = BANK_CONFIGS[connection.bank_name]
    bank_access_token = await get_bank_token(connection.bank_name)
    
    # Логика выбора URL для проверки остается той же
    if connection.status == "awaitingauthorization":
        check_url = f"{config['base_url']}/account-consents/{connection.request_id}"
        headers = {"Authorization": f"Bearer {bank_access_token}", "X-Requesting-Bank": config['client_id']}
    else: # status == "active"
        check_url = f"{config['base_url']}/account-consents/{connection.consent_id}"
        headers = {"Authorization": f"Bearer {bank_access_token}", "x-fapi-interaction-id": config['client_id']}

    async with httpx.AsyncClient() as client:
        response = await client.get(check_url, headers=headers)
    log_response(response)

    if response.status_code != 200: raise HTTPException(status_code=500, detail=f"Failed to check consent status: {response.text}")
    
    consent_data = response.json().get("data", {})
    
    # ИЗМЕНЕНИЕ: Новая, более надежная логика обработки статусов
    api_status = consent_data.get("status", "unknown").lower()

    if api_status == "authorized":
        # Сценарий "Успех"
        if connection.status == "awaitingauthorization":
            connection.consent_id = consent_data['consentId']
        connection.status = "active"
        db.commit()
        
        accounts_data = await fetch_accounts(bank_access_token, connection.consent_id, connection.bank_client_id, connection.bank_name)
        try:
            name = accounts_data.get("data", {}).get("account", [{}])[0].get("account", [{}])[0].get("name")
            if name and connection.full_name != name: connection.full_name = name; db.commit()
        except Exception: pass
        
        return {"status": "success_approved", "message": "Consent is active and data fetched!", "accounts_data": accounts_data}
    
    elif api_status == "rejected":
        # Сценарий "Отказ"
        logger.info(f"Согласие для connection_id {connection_id} было отклонено пользователем.")
        connection.status = "rejected"
        db.commit()
        return {"status": "rejected", "message": "User has rejected the consent request."}
        
    else:
        # Сценарий "Все остальное" (включая "awaitingauthorization", "expired" и т.д.)
        logger.info(f"Состояние согласия для connection_id {connection_id}: '{api_status}'")
        # Обновляем статус в нашей БД, если он изменился
        if connection.status != api_status:
            connection.status = api_status
            db.commit()
        return {"status": api_status, "message": f"Consent status is '{api_status}'. Please try again later."}

@app.delete("/connection/{connection_id}", summary="Шаг 3: Отозвать согласие и удалить подключение")
async def delete_connection(connection_id: int, db: Session = Depends(get_db)):
    """
    Удаляет подключение. Если имеется идентификатор (consent_id или request_id),
    сначала отзывает его в банке, а затем удаляет запись из локальной базы данных.
    """
    logger.info(f"Запрос на удаление подключения с ID: {connection_id}")
    
    connection = db.query(models.ConnectedBank).filter(models.ConnectedBank.id == connection_id).first()
    if not connection:
        logger.warning(f"Подключение с ID {connection_id} не найдено в базе данных.")
        raise HTTPException(status_code=404, detail="Connection not found")

    # --- ИЗМЕНЕНИЕ: Определяем, какой ID использовать для отзыва ---
    id_to_revoke = None
    if connection.consent_id:
        id_to_revoke = connection.consent_id
    elif connection.request_id:
        id_to_revoke = connection.request_id

    # Если есть что отзывать (любой из ID), отправляем запрос в банк
    if id_to_revoke:
        logger.info(f"Найден ID для отзыва: {id_to_revoke}. Попытка отзыва в банке {connection.bank_name}.")
        config = BANK_CONFIGS[connection.bank_name]
        
        # Используем универсальный ID в URL
        revoke_url = f"{config['base_url']}/account-consents/{id_to_revoke}"
        headers = {
            "x-fapi-interaction-id": config['client_id']
        }

        async with httpx.AsyncClient() as client:
            request = client.build_request("DELETE", revoke_url, headers=headers)
            log_request(request)
            response = await client.delete(revoke_url, headers=headers)
            log_response(response)
        
        # Успешный отзыв - 204 No Content.
        # Ошибка 404 (Not Found) также приемлема - значит, ресурс уже недействителен.
        if response.status_code not in [204, 404]:
            logger.error(f"Банк вернул непредвиденную ошибку при отзыве ресурса {id_to_revoke}: {response.text}")
            # Несмотря на ошибку, мы все равно удалим запись локально
    
    else:
        # Если нет ни consent_id, ни request_id (теоретически невозможно, но для надежности)
        logger.info(f"В записи отсутствует идентификатор для отзыва. Пропускаем шаг отзыва в банке.")

    # Вне зависимости от исхода отзыва, удаляем запись из нашей локальной базы данных.
    logger.info(f"Удаление записи о подключении ID {connection_id} из локальной базы данных.")
    db.delete(connection)
    db.commit()

    return {"status": "deleted", "message": "Connection record successfully deleted from the database."}