# finance-app-master/payment_consents_api.py
import httpx
from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

import models
from database import get_db
from deps import user_is_admin_or_self
from schemas import (
    PaymentConsentInitiate,
    PaymentConsentResponse,
    PaymentConsentListResponse,
)
from utils import get_bank_token, log_response

router = APIRouter(
    prefix="/users/{user_id}/payment-consents",
    tags=["payment_consents"],
)


async def _revoke_payment_consent(consent: models.PaymentConsent, db: Session):
    """Отзывает согласие на платеж в банке."""
    id_to_revoke = consent.consent_id or consent.request_id
    if not id_to_revoke:
        return

    bank_config = db.query(models.Bank).filter(models.Bank.name == consent.bank_name).first()
    if not bank_config:
        print(f"Bank config for {consent.bank_name} not found, skipping revocation.")
        return

    revoke_url = f"{bank_config.base_url}/payment-consents/{id_to_revoke}"
    
    # Для отзыва согласия на платеж требуется токен доступа к банку
    bank_access_token = await get_bank_token(consent.bank_name, db)
    headers = {"Authorization": f"Bearer {bank_access_token}"}

    async with httpx.AsyncClient() as client:
        response = await client.delete(revoke_url, headers=headers)
        log_response(response)


@router.post("/", response_model=PaymentConsentResponse, summary="Инициировать согласие на платеж")
async def initiate_payment_consent(
    user_id: int,
    consent_data: PaymentConsentInitiate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self),
):
    """Создает запрос на согласие для совершения платежа."""
    bank_config = db.query(models.Bank).filter(models.Bank.name == consent_data.bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=404, detail=f"Bank '{consent_data.bank_name}' not found.")

    bank_access_token = await get_bank_token(consent_data.bank_name, db)
    
    request_url = f"{bank_config.base_url}/payment-consents/request"
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "Content-Type": "application/json",
        "X-Requesting-Bank": bank_config.client_id,
    }
    
    # Формируем тело запроса к API банка на основе pydantic модели
    api_body = {
        "requesting_bank": bank_config.client_id,
        "client_id": consent_data.bank_client_id,
        "consent_type": consent_data.consent_type,
        "debtor_account": consent_data.debtor_account,
        "creditor_name": consent_data.creditor_name,
        "creditor_account": consent_data.creditor_account,
        "amount": float(consent_data.amount),
        "currency": consent_data.currency,
        "reference": consent_data.reference,
    }

    async with httpx.AsyncClient() as client:
        response = await client.post(request_url, headers=headers, json=api_body)
    
    log_response(response)
    if response.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Failed to create payment consent: {response.text}")

    response_data = response.json()
    
    new_consent = models.PaymentConsent(
        user_id=user_id,
        bank_name=consent_data.bank_name,
        bank_client_id=consent_data.bank_client_id,
        request_id=response_data.get("request_id"),
        consent_id=response_data.get("consent_id"), # Может быть null
        status=response_data.get("status", "awaitingauthorization").lower(),
        details=api_body # Сохраняем детали платежа
    )
    db.add(new_consent)
    db.commit()
    db.refresh(new_consent)

    return new_consent


@router.get("/", response_model=PaymentConsentListResponse, summary="Получить список согласий на платежи")
def list_payment_consents(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """Возвращает все сохраненные согласия на платежи для пользователя."""
    consents = db.query(models.PaymentConsent).filter(models.PaymentConsent.user_id == user_id).all()
    return {"count": len(consents), "consents": consents}


@router.post("/{consent_db_id}", response_model=PaymentConsentResponse, summary="Проверить статус согласия на платеж")
async def check_payment_consent_status(
    user_id: int,
    consent_db_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self),
):
    """Проверяет статус ранее инициированного согласия в банке и обновляет его в БД."""
    consent = db.query(models.PaymentConsent).filter(
        models.PaymentConsent.id == consent_db_id,
        models.PaymentConsent.user_id == user_id
    ).first()
    if not consent:
        raise HTTPException(status_code=404, detail="Payment consent not found.")
    
    if consent.status not in ["awaitingauthorization"]:
        return consent # Возвращаем как есть, статус уже финальный
        
    bank_config = db.query(models.Bank).filter(models.Bank.name == consent.bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail="Bank configuration not found.")

    bank_access_token = await get_bank_token(consent.bank_name, db)
    check_url = f"{bank_config.base_url}/payment-consents/{consent.request_id}"
    headers = {"Authorization": f"Bearer {bank_access_token}"}
    
    async with httpx.AsyncClient() as client:
        response = await client.get(check_url, headers=headers)
    
    log_response(response)
    if response.status_code != 200:
        raise HTTPException(status_code=502, detail=f"Failed to check consent status: {response.text}")
        
    response_data = response.json()
    api_status = response_data.get("status", "unknown").lower()
    
    if api_status != consent.status:
        consent.status = api_status
        if api_status == "authorized" and response_data.get("consent_id"):
            consent.consent_id = response_data["consent_id"]
        db.commit()
        db.refresh(consent)
        
    return consent


@router.delete("/{consent_db_id}", summary="Удалить/отозвать согласие на платеж")
async def delete_payment_consent(
    user_id: int,
    consent_db_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self),
):
    """Отзывает согласие в банке (если возможно) и удаляет его из БД."""
    consent = db.query(models.PaymentConsent).filter(
        models.PaymentConsent.id == consent_db_id,
        models.PaymentConsent.user_id == user_id
    ).first()

    if not consent:
        raise HTTPException(status_code=404, detail="Payment consent not found.")

    await _revoke_payment_consent(consent, db)
    
    db.delete(consent)
    db.commit()
    
    return {"status": "deleted", "message": "Payment consent has been revoked and deleted."}