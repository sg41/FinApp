import httpx
import logging
from sqlalchemy.orm import Session
from typing import Optional

from models import ConnectedBank
from database import get_db  # не нужен напрямую, но модели нужны
from config import BANK_CONFIGS

logger = logging.getLogger("uvicorn")


async def revoke_bank_consent(connection: ConnectedBank) -> None:
    """
    Отзывает согласие (consent или request) в банке по данным подключения.
    """
    id_to_revoke = connection.consent_id or connection.request_id
    if not id_to_revoke:
        return  # Нечего отзывать

    bank_name = connection.bank_name
    if bank_name not in BANK_CONFIGS:
        logger.warning(f"Unknown bank '{bank_name}' for connection {connection.id}. Skipping revocation.")
        return

    config = BANK_CONFIGS[bank_name]
    revoke_url = f"{config['base_url'].strip()}/account-consents/{id_to_revoke}"
    headers = {"x-fapi-interaction-id": config['client_id']}

    try:
        async with httpx.AsyncClient() as client:
            response = await client.delete(revoke_url, headers=headers)
        logger.info(f"Revoked consent {id_to_revoke} at {revoke_url}: status {response.status_code}")
        if response.status_code not in (204, 404):
            logger.error(f"Unexpected status on revoke: {response.status_code}, body: {response.text}")
    except Exception as e:
        logger.error(f"Failed to revoke consent {id_to_revoke} for bank {bank_name}: {e}")