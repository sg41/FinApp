# finance-app-master/payments_api.py
import httpx
import uuid
from fastapi import APIRouter, Depends, HTTPException, Path
from sqlalchemy.orm import Session

import models
from database import get_db
from deps import user_is_admin_or_self
from schemas import (
    PaymentInitiate,
    InternalTransferInitiate,
    PaymentStatusResponse,
)
from utils import get_bank_token, log_response

router = APIRouter(
    prefix="/users/{user_id}/payments",
    tags=["payments"]
)


@router.post(
    "/",
    summary="Совершить платеж на внешний счет"
)
async def create_payment(
    user_id: int,
    payment_data: PaymentInitiate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Инициирует разовый платеж на внешний счет, используя ранее полученное и
    авторизованное согласие на платеж.
    """
    # ... (логика до формирования заголовков остается без изменений) ...
    # 1-4 шаги
    debtor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == payment_data.debtor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()
    if not debtor_account:
        raise HTTPException(status_code=404, detail="Debtor account not found or access denied.")
    consent = db.query(models.PaymentConsent).filter(
        models.PaymentConsent.id == payment_data.payment_consent_id,
        models.PaymentConsent.user_id == user_id
    ).first()
    if not consent:
        raise HTTPException(status_code=404, detail="Payment consent not found.")
    if consent.status != 'approved':
        raise HTTPException(status_code=400, detail=f"Consent is not approved. Current status: {consent.status}")
    if not consent.consent_id:
        raise HTTPException(status_code=400, detail="API Consent ID is missing for this consent record.")
    if debtor_account.bank_name != consent.bank_name:
        raise HTTPException(status_code=400, detail="Account and consent must belong to the same bank.")
    bank_config = db.query(models.Bank).filter(models.Bank.name == debtor_account.bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail=f"Bank configuration for {debtor_account.bank_name} not found.")
    bank_access_token = await get_bank_token(bank_config.name, db)
    debtor_account_number = None
    if debtor_account.owner_data and isinstance(debtor_account.owner_data, list) and debtor_account.owner_data:
        debtor_account_number = debtor_account.owner_data[0].get("identification")
    if not debtor_account_number:
        raise HTTPException(status_code=500, detail="Could not determine debtor account number from stored data.")

    api_body = {
        "data": {
            "initiation": {
                "instructedAmount": {
                    "amount": str(payment_data.amount),
                    "currency": payment_data.currency,
                },
                "debtorAccount": {
                    "schemeName": "RU.CBR.PAN",
                    "identification": debtor_account_number,
                },
                "creditorAccount": {
                    "schemeName": "RU.CBR.PAN",
                    "identification": payment_data.creditor_account,
                    "bank_code": payment_data.creditor_bank_code,
                    "name": payment_data.creditor_name,
                },
                "comment": payment_data.reference,
            }
        }
    }
    
    # 6. Сформировать заголовки
    idempotency_key = str(uuid.uuid4())
    # --- vvv ИЗМЕНЕНИЕ: Используем правильный заголовок для ID согласия на платеж vvv ---
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "X-Requesting-Bank": bank_config.client_id,
        "x-payment-consent-id": consent.consent_id, # <-- ИСПРАВЛЕНО
        "X-Idempotency-Key": idempotency_key,
        "X-Fapi-Interaction-Id": idempotency_key,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    # --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
    
    params = {"client_id": debtor_account.connection.bank_client_id}
    
    # 7. Отправить запрос
    payment_url = f"{bank_config.base_url}/payments"
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(payment_url, headers=headers, params=params, json=api_body)
            log_response(response)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=f"Bank API error: {e.response.text}")
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to bank API: {e}")

@router.post(
    "/internal-transfer",
    summary="Совершить перевод между своими счетами"
)
async def create_internal_transfer(
    user_id: int,
    transfer_data: InternalTransferInitiate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Инициирует перевод между двумя счетами одного и того же пользователя.
    Может использоваться для переводов между счетами в разных банках.
    """
    # ... (логика до формирования заголовков остается без изменений) ...
    # 1-4 шаги
    debtor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == transfer_data.debtor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()
    creditor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == transfer_data.creditor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()
    if not debtor_account or not creditor_account:
        raise HTTPException(status_code=404, detail="One or both accounts not found or access denied.")
    consent = db.query(models.PaymentConsent).filter(
        models.PaymentConsent.id == transfer_data.payment_consent_id,
        models.PaymentConsent.user_id == user_id,
        models.PaymentConsent.bank_name == debtor_account.bank_name
    ).first()
    if not consent:
        raise HTTPException(status_code=404, detail="Payment consent for the debtor bank not found.")
    if consent.status != 'approved':
        raise HTTPException(status_code=400, detail=f"Consent is not approved. Current status: {consent.status}")
    if not consent.consent_id:
        raise HTTPException(status_code=400, detail="API Consent ID is missing for this consent record.")
    bank_config = db.query(models.Bank).filter(models.Bank.name == debtor_account.bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail=f"Bank configuration for {debtor_account.bank_name} not found.")
    bank_access_token = await get_bank_token(bank_config.name, db)
    debtor_account_number = None
    if debtor_account.owner_data and isinstance(debtor_account.owner_data, list) and debtor_account.owner_data:
        debtor_account_number = debtor_account.owner_data[0].get("identification")
    creditor_account_number = None
    creditor_name = None
    if creditor_account.owner_data and isinstance(creditor_account.owner_data, list) and creditor_account.owner_data:
        creditor_account_number = creditor_account.owner_data[0].get("identification")
        creditor_name = creditor_account.owner_data[0].get("name")
    if not debtor_account_number or not creditor_account_number or not creditor_name:
        raise HTTPException(status_code=500, detail="Could not determine account numbers or owner name from stored data.")

    api_body = {
        "data": {
            "initiation": {
                "instructedAmount": {
                    "amount": str(transfer_data.amount),
                    "currency": transfer_data.currency,
                },
                "debtorAccount": {
                    "schemeName": "RU.CBR.PAN",
                    "identification": debtor_account_number,
                },
                "creditorAccount": {
                    "schemeName": "RU.CBR.PAN",
                    "identification": creditor_account_number,
                    "bank_code": creditor_account.bank_name,
                    "name": creditor_name,
                },
                "comment": transfer_data.reference,
            }
        }
    }

    # 5. Сформировать заголовки
    idempotency_key = str(uuid.uuid4())
    # --- vvv ИЗМЕНЕНИЕ: Используем правильный заголовок для ID согласия на платеж vvv ---
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "X-Requesting-Bank": bank_config.client_id,
        "x-payment-consent-id": consent.consent_id, # <-- ИСПРАВЛЕНО
        "X-Idempotency-Key": idempotency_key,
        "X-Fapi-Interaction-Id": idempotency_key,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    # --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
    
    params = {"client_id": debtor_account.connection.bank_client_id}

    # 6. Отправить запрос
    payment_url = f"{bank_config.base_url}/payments"
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(payment_url, headers=headers, params=params, json=api_body)
            log_response(response)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=f"Bank API error: {e.response.text}")
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to bank API: {e}")

@router.get(
    "/{bank_name}/{bank_client_id}/{payment_id}",
    response_model=PaymentStatusResponse,
    summary="Получить статус платежа"
)
async def get_payment_status(
    user_id: int,
    bank_name: str = Path(..., description="Символьное имя банка (vbank, abank, etc.)"),
    bank_client_id: str = Path(..., description="ID клиента в банке"),
    payment_id: str = Path(..., description="ID платежа, полученный от банка"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Получает актуальный статус ранее созданного платежа из API банка.
    """
    # 1. Проверить, что у пользователя есть активное подключение для этого банка и клиента
    connection = db.query(models.ConnectedBank).filter(
        models.ConnectedBank.user_id == user_id,
        models.ConnectedBank.bank_name == bank_name,
        models.ConnectedBank.bank_client_id == bank_client_id,
        models.ConnectedBank.status == "active"
    ).first()
    if not connection:
        raise HTTPException(status_code=403, detail="Active connection for this bank and client ID not found.")

    # 2. Получить конфигурацию банка и токен
    bank_config = db.query(models.Bank).filter(models.Bank.name == bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail=f"Bank configuration for {bank_name} not found.")
    
    bank_access_token = await get_bank_token(bank_config.name, db)

    # 3. Сформировать запрос к API банка
    status_url = f"{bank_config.base_url}/payments/{payment_id}"
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "Accept": "application/json"
    }
    params = { "client_id": bank_client_id }

    # 4. Отправить запрос
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(status_url, headers=headers, params=params)
            log_response(response)
            response.raise_for_status()
            return response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=f"Bank API error: {e.response.text}")
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to bank API: {e}")