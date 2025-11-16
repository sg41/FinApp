# finance-app-master/payments_api.py
import httpx
import uuid
from fastapi import APIRouter, Depends, HTTPException, Path
from sqlalchemy.orm import Session
from typing import List

import models
from database import get_db
from deps import user_is_admin_or_self
from schemas import (
    PaymentInitiate,
    InternalTransferInitiate,
    PaymentStatusResponse,
    PaymentResponse,
    PaymentListResponse,
)
from utils import get_bank_token, log_response

router = APIRouter(
    prefix="/users/{user_id}/payments",
    tags=["payments"]
)


@router.post(
    "/",
    response_model=PaymentStatusResponse,
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
    авторизованное согласие на платеж. После успеха сохраняет запись в историю.
    """
    # 1. Найти счет списания и проверить, что он принадлежит пользователю
    debtor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == payment_data.debtor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()
    if not debtor_account:
        raise HTTPException(status_code=404, detail="Debtor account not found or access denied.")

    # 2. Найти согласие на платеж и проверить его
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
    
    # 3. Проверить, что счет и согласие относятся к одному и тому же банку
    if debtor_account.bank_name != consent.bank_name:
        raise HTTPException(status_code=400, detail="Account and consent must belong to the same bank.")

    # 4. Получить конфигурацию банка и токен
    bank_config = db.query(models.Bank).filter(models.Bank.name == debtor_account.bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail=f"Bank configuration for {debtor_account.bank_name} not found.")

    bank_access_token = await get_bank_token(bank_config.name, db)
    
    # 5. Сформировать тело запроса для API банка
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
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "X-Requesting-Bank": bank_config.client_id,
        "x-payment-consent-id": consent.consent_id,
        "X-Idempotency-Key": idempotency_key,
        "X-Fapi-Interaction-Id": idempotency_key,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    
    params = {"client_id": debtor_account.connection.bank_client_id}
    
    # 7. Отправить запрос
    payment_url = f"{bank_config.base_url}/payments"
    bank_response_json = {}
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(payment_url, headers=headers, params=params, json=api_body)
            log_response(response)
            response.raise_for_status()
            bank_response_json = response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=f"Bank API error: {e.response.text}")
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to bank API: {e}")

    # 8. Сохранение платежа в БД
    if bank_response_json:
        bank_payment_data = bank_response_json.get("data", {})
        new_payment = models.Payment(
            user_id=user_id,
            debtor_account_id=payment_data.debtor_account_id,
            consent_id=payment_data.payment_consent_id,
            bank_payment_id=bank_payment_data.get("paymentId"),
            status=bank_payment_data.get("status", "pending").lower(),
            amount=payment_data.amount,
            currency=payment_data.currency,
            creditor_details={
                "name": payment_data.creditor_name,
                "account": payment_data.creditor_account,
                "bank_code": payment_data.creditor_bank_code,
            },
            idempotency_key=idempotency_key,
            bank_name=debtor_account.bank_name,
            bank_client_id=debtor_account.connection.bank_client_id,
        )
        db.add(new_payment)
        db.commit()

    return bank_response_json


@router.post(
    "/internal-transfer",
    response_model=PaymentStatusResponse,
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
    После успеха сохраняет запись в историю.
    """
    # 1. Найти счета
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
    
    # 2. Найти согласие
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

    # 3. Получить конфигурацию банка-отправителя
    bank_config = db.query(models.Bank).filter(models.Bank.name == debtor_account.bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail=f"Bank configuration for {debtor_account.bank_name} not found.")

    bank_access_token = await get_bank_token(bank_config.name, db)
    
    # 4. Собрать данные для API
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
                "debtorAccount": { "schemeName": "RU.CBR.PAN", "identification": debtor_account_number },
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
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "X-Requesting-Bank": bank_config.client_id,
        "x-payment-consent-id": consent.consent_id,
        "X-Idempotency-Key": idempotency_key,
        "X-Fapi-Interaction-Id": idempotency_key,
        "Content-Type": "application/json",
        "Accept": "application/json"
    }
    
    params = {"client_id": debtor_account.connection.bank_client_id}

    # 6. Отправить запрос
    payment_url = f"{bank_config.base_url}/payments"
    bank_response_json = {}
    async with httpx.AsyncClient() as client:
        try:
            response = await client.post(payment_url, headers=headers, params=params, json=api_body)
            log_response(response)
            response.raise_for_status()
            bank_response_json = response.json()
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=f"Bank API error: {e.response.text}")
        except httpx.RequestError as e:
            raise HTTPException(status_code=502, detail=f"Could not connect to bank API: {e}")
            
    # 7. Сохранить платеж в БД
    if bank_response_json:
        bank_payment_data = bank_response_json.get("data", {})
        new_payment = models.Payment(
            user_id=user_id,
            debtor_account_id=transfer_data.debtor_account_id,
            consent_id=transfer_data.payment_consent_id,
            bank_payment_id=bank_payment_data.get("paymentId"),
            status=bank_payment_data.get("status", "pending").lower(),
            amount=transfer_data.amount,
            currency=transfer_data.currency,
            creditor_details={
                "internal_account_id": transfer_data.creditor_account_id,
                "name": creditor_name,
                "account": creditor_account_number,
                "bank_code": creditor_account.bank_name,
            },
            idempotency_key=idempotency_key,
            bank_name=debtor_account.bank_name,
            bank_client_id=debtor_account.connection.bank_client_id,
        )
        db.add(new_payment)
        db.commit()

    return bank_response_json


@router.get(
    "/history",
    response_model=PaymentListResponse,
    summary="Получить историю совершенных платежей"
)
def get_payment_history(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Возвращает список всех платежей, инициированных пользователем через API.
    """
    payments = db.query(models.Payment).filter(models.Payment.user_id == user_id).order_by(models.Payment.created_at.desc()).all()
    return {"count": len(payments), "payments": payments}


@router.post(
    "/{payment_db_id}/refresh-status",
    response_model=PaymentResponse,
    summary="Обновить статус сохраненного платежа"
)
async def refresh_payment_status(
    user_id: int,
    payment_db_id: int = Path(..., description="ID платежа в НАШЕЙ базе данных"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Запрашивает у банка актуальный статус платежа и обновляет его в нашей БД.
    """
    payment = db.query(models.Payment).filter(
        models.Payment.id == payment_db_id,
        models.Payment.user_id == user_id
    ).first()
    if not payment:
        raise HTTPException(status_code=404, detail="Payment not found.")

    updated_status_data = await get_payment_status(
        user_id=user_id,
        bank_name=payment.bank_name,
        bank_client_id=payment.bank_client_id,
        payment_id=payment.bank_payment_id,
        db=db,
        current_user=current_user
    )
    
    new_status = updated_status_data.data.status.lower()
    if payment.status != new_status:
        payment.status = new_status
        db.commit()
        db.refresh(payment)
        
    return payment


@router.get(
    "/{bank_name}/{bank_client_id}/{payment_id}",
    response_model=PaymentStatusResponse,
    summary="Получить статус платежа (служебный)"
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
    connection = db.query(models.ConnectedBank).filter(
        models.ConnectedBank.user_id == user_id,
        models.ConnectedBank.bank_name == bank_name,
        models.ConnectedBank.bank_client_id == bank_client_id,
        models.ConnectedBank.status == "active"
    ).first()
    if not connection:
        raise HTTPException(status_code=403, detail="Active connection for this bank and client ID not found.")

    bank_config = db.query(models.Bank).filter(models.Bank.name == bank_name).first()
    if not bank_config:
        raise HTTPException(status_code=500, detail=f"Bank configuration for {bank_name} not found.")
    
    bank_access_token = await get_bank_token(bank_config.name, db)

    status_url = f"{bank_config.base_url}/payments/{payment_id}"
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "Accept": "application/json"
    }
    params = { "client_id": bank_client_id }

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