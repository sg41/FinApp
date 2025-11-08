# finance-app-master/transactions_api.py
import httpx
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import Optional
from datetime import datetime, timezone
from decimal import Decimal

import models
from database import get_db
from deps import user_is_admin_or_self
from utils import get_bank_token
from schemas import TransactionListResponse, TurnoverResponse, TransactionDetail

router = APIRouter(
    prefix="/users/{user_id}/banks/{bank_id}/accounts",
    tags=["transactions"]
)

@router.get(
    "/{api_account_id}/transactions",
    response_model=TransactionListResponse,
    summary="Получить транзакции по ID счета и ID банка"
)
async def get_transactions(
    user_id: int,
    bank_id: int,
    api_account_id: str,
    from_booking_date_time: Optional[datetime] = Query(None, description="Начало периода в формате ISO 8601"),
    to_booking_date_time: Optional[datetime] = Query(None, description="Конец периода в формате ISO 8601"),
    page: int = Query(1, ge=1, description="Номер страницы"),
    limit: int = Query(50, ge=1, le=100, description="Количество элементов на странице"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Запрашивает и возвращает список транзакций для конкретного счета,
    однозначно определенного по ID банка и ID счета.
    """
    bank = db.query(models.Bank).filter(models.Bank.id == bank_id).first()
    if not bank:
        raise HTTPException(status_code=404, detail="Bank with the specified ID not found.")

    db_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.api_account_id == api_account_id,
        models.ConnectedBank.user_id == user_id,
        models.ConnectedBank.bank_name == bank.name
    ).first()

    if not db_account:
        raise HTTPException(status_code=404, detail="Account not found for the specified bank or access denied.")

    connection = db_account.connection
    if not connection or connection.status != "active" or not connection.consent_id:
        raise HTTPException(status_code=403, detail="Active connection with consent is required.")

    bank_access_token = await get_bank_token(connection.bank_name, db)
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "X-Requesting-Bank": bank.client_id,
        "X-Consent-Id": connection.consent_id,
        "Accept": "application/json"
    }
    transactions_url = f"{bank.base_url}/accounts/{api_account_id}/transactions"
    
    params = {"page": page, "limit": limit}
    if from_booking_date_time:
        params["from_booking_date_time"] = from_booking_date_time.isoformat()
    if to_booking_date_time:
        params["to_booking_date_time"] = to_booking_date_time.isoformat()
    
    async with httpx.AsyncClient() as client:
        try:
            response = await client.get(transactions_url, headers=headers, params=params)
            response.raise_for_status()
            response_data = response.json()

            if (from_booking_date_time or to_booking_date_time) and "data" in response_data:
                original_transactions = response_data["data"].get("transaction", [])
                filtered_transactions = []
                
                from_utc = from_booking_date_time.replace(tzinfo=timezone.utc) if from_booking_date_time and from_booking_date_time.tzinfo is None else from_booking_date_time
                to_utc = to_booking_date_time.replace(tzinfo=timezone.utc) if to_booking_date_time and to_booking_date_time.tzinfo is None else to_booking_date_time

                for trans_data in original_transactions:
                    try:
                        transaction = TransactionDetail(**trans_data)
                        is_in_date_range = True
                        if from_utc and transaction.bookingDateTime < from_utc:
                            is_in_date_range = False
                        if to_utc and transaction.bookingDateTime > to_utc:
                            is_in_date_range = False
                        
                        if is_in_date_range:
                            filtered_transactions.append(trans_data)
                    except Exception:
                        continue 

                response_data["data"]["transaction"] = filtered_transactions
                
            return response_data
        except httpx.HTTPStatusError as e:
            raise HTTPException(status_code=e.response.status_code, detail=f"Error from bank API: {e.response.text}")
        except (httpx.RequestError, Exception) as e:
            raise HTTPException(status_code=502, detail=f"Failed to fetch transactions from {connection.bank_name}: {e}")


@router.get(
    "/{api_account_id}/turnover",
    response_model=TurnoverResponse,
    summary="Получить обороты по ID счета и ID банка за период"
)
async def get_account_turnover(
    user_id: int,
    bank_id: int,
    api_account_id: str,
    from_booking_date_time: Optional[datetime] = Query(None, description="Начало периода в формате ISO 8601"),
    to_booking_date_time: Optional[datetime] = Query(None, description="Конец периода в формате ISO 8601"),
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Рассчитывает обороты для конкретного счета,
    однозначно определенного по ID банка и ID счета.
    """
    bank = db.query(models.Bank).filter(models.Bank.id == bank_id).first()
    if not bank:
        raise HTTPException(status_code=404, detail="Bank with the specified ID not found.")

    db_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.api_account_id == api_account_id,
        models.ConnectedBank.user_id == user_id,
        models.ConnectedBank.bank_name == bank.name
    ).first()

    if not db_account:
        raise HTTPException(status_code=404, detail="Account not found for the specified bank or access denied.")

    connection = db_account.connection
    if not connection or connection.status != "active" or not connection.consent_id:
        raise HTTPException(status_code=403, detail="Active connection with consent is required.")

    bank_access_token = await get_bank_token(connection.bank_name, db)
    headers = {
        "Authorization": f"Bearer {bank_access_token}",
        "X-Requesting-Bank": bank.client_id,
        "X-Consent-Id": connection.consent_id,
        "Accept": "application/json"
    }
    transactions_url = f"{bank.base_url}/accounts/{api_account_id}/transactions"
    
    base_params = {"limit": 100}
    if from_booking_date_time:
        base_params["from_booking_date_time"] = from_booking_date_time.isoformat()
    if to_booking_date_time:
        base_params["to_booking_date_time"] = to_booking_date_time.isoformat()

    total_credit = Decimal("0.0")
    total_debit = Decimal("0.0")
    currency = None
    page = 1
    
    from_utc = from_booking_date_time.replace(tzinfo=timezone.utc) if from_booking_date_time and from_booking_date_time.tzinfo is None else from_booking_date_time
    to_utc = to_booking_date_time.replace(tzinfo=timezone.utc) if to_booking_date_time and to_booking_date_time.tzinfo is None else to_booking_date_time

    async with httpx.AsyncClient() as client:
        while True:
            current_params = base_params.copy()
            current_params["page"] = page
            
            try:
                response = await client.get(transactions_url, headers=headers, params=current_params)
                response.raise_for_status()
                response_data = response.json()
                transactions = response_data.get("data", {}).get("transaction", [])
                
                if not transactions:
                    break
                
                for trans_data in transactions:
                    try:
                        transaction = TransactionDetail(**trans_data)
                        
                        is_in_date_range = True
                        if from_utc and transaction.bookingDateTime < from_utc:
                            is_in_date_range = False
                        if to_utc and transaction.bookingDateTime > to_utc:
                            is_in_date_range = False
                        
                        if not is_in_date_range:
                            continue

                        if currency is None:
                            currency = transaction.amount.currency
                        
                        amount_decimal = Decimal(transaction.amount.amount)
                        if transaction.creditDebitIndicator.lower() == 'credit':
                            total_credit += amount_decimal
                        elif transaction.creditDebitIndicator.lower() == 'debit':
                            total_debit += amount_decimal
                            
                    except Exception:
                        continue
                page += 1
            except httpx.HTTPStatusError as e:
                raise HTTPException(status_code=e.response.status_code, detail=f"Error from bank API: {e.response.text}")
            except (httpx.RequestError, Exception) as e:
                raise HTTPException(status_code=502, detail=f"Failed to fetch transactions from {connection.bank_name}: {e}")

    return TurnoverResponse(
        account_id=api_account_id,
        total_credit=total_credit,
        total_debit=total_debit,
        currency=currency or db_account.currency or "N/A",
        period_from=from_booking_date_time,
        period_to=to_booking_date_time
    )