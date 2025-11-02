# main.py
import os
import secrets
import httpx
from datetime import datetime, timedelta

from fastapi import FastAPI, Depends, HTTPException
from sqlalchemy.orm import Session

# Импортируем наши модули
from . import models
from .database import engine, get_db
from .encryption_service import encrypt_data

# Создаем все таблицы в БД при запуске (для простоты)
models.Base.metadata.create_all(bind=engine)

app = FastAPI()

# Временное хранилище для state. В реальном приложении используйте сессии или Redis.
STATE_STORAGE = {}

# Конфигурация банков (берем из .env)
BANK_CONFIGS = {
    "vbank": {
        "client_id": os.getenv("VBANK_CLIENT_ID"),
        "client_secret": os.getenv("VBANK_CLIENT_SECRET"),
        "auth_url": "https://vbank.open.bankingapi.ru/auth/authorize",
        "token_url": "https://vbank.open.bankingapi.ru/auth/token",
        "redirect_uri": "http://127.0.0.1:8000/callback/vbank"
    },
    # Можно добавить a-bank и s-bank по аналогии
}

@app.get("/connect/{bank_name}")
async def get_connection_link(bank_name: str):
    """
    Шаг 1: Инициировать подключение.
    Возвращает ссылку, на которую нужно перенаправить пользователя.
    """
    if bank_name not in BANK_CONFIGS:
        raise HTTPException(status_code=404, detail="Bank not found")
    
    config = BANK_CONFIGS[bank_name]
    state = secrets.token_urlsafe(16)
    
    # Сохраняем state для последующей проверки (привязав к сессии или user_id)
    # Для теста просто сохраним в словарь
    STATE_STORAGE['latest_state'] = state
    
    params = {
        "response_type": "code",
        "client_id": config['client_id'],
        "scope": "accounts payments consents", # Запрашиваем нужные разрешения
        "redirect_uri": config['redirect_uri'],
        "state": state,
    }
    
    # Используем httpx.Request для корректного формирования URL с параметрами
    request = httpx.Request("GET", config['auth_url'], params=params)
    
    return {"authorization_url": str(request.url)}


@app.get("/callback/{bank_name}")
async def handle_bank_callback(bank_name: str, code: str, state: str, db: Session = Depends(get_db)):
    """
    Шаг 2: Обработка callback от банка.
    Обменивает code на access_token и сохраняет его в БД.
    """
    # Проверяем state для защиты от CSRF
    expected_state = STATE_STORAGE.get('latest_state')
    if not expected_state or expected_state != state:
        raise HTTPException(status_code=400, detail="Invalid state parameter")

    config = BANK_CONFIGS[bank_name]
    
    # Шаг 3: Обмен кода на токен
    token_data = {
        "grant_type": "authorization_code",
        "code": code,
        "redirect_uri": config['redirect_uri'],
    }
    
    async with httpx.AsyncClient() as client:
        response = await client.post(
            config['token_url'],
            data=token_data,
            auth=(config['client_id'], config['client_secret'])
        )
    
    if response.status_code != 200:
        raise HTTPException(status_code=response.status_code, detail=response.json())
        
    token_json = response.json()
    
    # Шаг 4: Шифруем и сохраняем токены в БД
    # Для примера привязываем к пользователю с ID=1
    # В реальном приложении здесь будет ID текущего залогиненного пользователя
    user_id = 1 
    
    # Создаем запись о подключенном банке
    new_connection = models.ConnectedBank(
        user_id=user_id,
        bank_name=bank_name,
        consent_id="consent-" + secrets.token_hex(8), # ID согласия придет в другом запросе, пока генерируем
        status="active"
    )
    db.add(new_connection)
    db.commit()
    db.refresh(new_connection)

    # Создаем запись с токенами
    new_token = models.AuthToken(
        connection_id=new_connection.id,
        encrypted_access_token=encrypt_data(token_json['access_token']),
        encrypted_refresh_token=encrypt_data(token_json['refresh_token']),
        expires_at=datetime.utcnow() + timedelta(seconds=token_json['expires_in'])
    )
    db.add(new_token)
    db.commit()
    
    return {"status": "success", "message": f"Bank {bank_name} connected successfully for user {user_id}"}