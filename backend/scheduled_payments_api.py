# finance-app-master/scheduled_payments_api.py

from fastapi import APIRouter, Depends, HTTPException
from sqlalchemy.orm import Session
from typing import List

import models
from database import get_db
from deps import user_is_admin_or_self
from schemas import (
    ScheduledPaymentCreate,
    ScheduledPaymentUpdate,
    ScheduledPaymentResponse,
    ScheduledPaymentListResponse
)

router = APIRouter(
    prefix="/users/{user_id}/scheduled-payments",
    tags=["scheduled-payments"]
)

@router.post("/", response_model=ScheduledPaymentResponse, summary="Создать новый автоплатеж")
def create_scheduled_payment(
    user_id: int,
    payment_data: ScheduledPaymentCreate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    # Проверки счетов остаются
    debtor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == payment_data.debtor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()
    if not debtor_account:
        raise HTTPException(status_code=404, detail="Debtor account not found or access denied.")

    creditor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == payment_data.creditor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()
    if not creditor_account:
        raise HTTPException(status_code=404, detail="Creditor account not found or access denied.")

    payment_dict = payment_data.model_dump()
    payment_dict['currency'] = debtor_account.currency
    
    # Преобразуем enums из схемы в enums для модели
    payment_dict['amount_type'] = models.ScheduledPaymentAmountType(payment_data.amount_type.value)
    if payment_data.recurrence_type:
        payment_dict['recurrence_type'] = models.RecurrenceType(payment_data.recurrence_type.value)
    
    new_payment = models.ScheduledPayment(**payment_dict, user_id=user_id)
    
    db.add(new_payment)
    db.commit()
    db.refresh(new_payment)
    return new_payment

@router.get("/", response_model=ScheduledPaymentListResponse, summary="Получить список автоплатежей")
def get_scheduled_payments(
    user_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    payments = db.query(models.ScheduledPayment).filter(models.ScheduledPayment.user_id == user_id).all()
    return {"count": len(payments), "payments": payments}

### НОВЫЙ ЭНДПОИНТ ДЛЯ ОБНОВЛЕНИЯ (PUT) ###
@router.put("/{payment_id}", response_model=ScheduledPaymentResponse, summary="Изменить автоплатеж")
def update_scheduled_payment(
    user_id: int,
    payment_id: int,
    update_data: ScheduledPaymentUpdate,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    db_payment = db.query(models.ScheduledPayment).filter(
        models.ScheduledPayment.id == payment_id,
        models.ScheduledPayment.user_id == user_id
    ).first()
    if not db_payment:
        raise HTTPException(status_code=404, detail="Scheduled payment not found.")

    update_dict = update_data.model_dump(exclude_unset=True)
    
    # Логика очистки полей
    final_amount_type = update_data.amount_type.value if 'amount_type' in update_dict else db_payment.amount_type.value
    if final_amount_type != 'fixed':
        update_dict['fixed_amount'] = None
    if final_amount_type != 'minimum_payment':
        update_dict['minimum_payment_percentage'] = None
    if final_amount_type == 'fixed':
        update_dict['period_start_date'] = None
        update_dict['period_end_date'] = None
        
    # Преобразование enums
    if 'amount_type' in update_dict and update_dict['amount_type'] is not None:
        update_dict['amount_type'] = models.ScheduledPaymentAmountType(update_data.amount_type.value)
    if 'recurrence_type' in update_dict:
        if update_data.recurrence_type:
            update_dict['recurrence_type'] = models.RecurrenceType(update_data.recurrence_type.value)
        else: # если прислали null
            update_dict['recurrence_interval'] = None

    # ... (остальная логика обновления) ...
    for key, value in update_dict.items():
        setattr(db_payment, key, value)
    
    db.commit()
    db.refresh(db_payment)
    return db_payment


### НОВЫЙ ЭНДПОИНТ ДЛЯ УДАЛЕНИЯ (DELETE) ###
@router.delete("/{payment_id}", summary="Удалить автоплатеж")
def delete_scheduled_payment(
    user_id: int,
    payment_id: int,
    db: Session = Depends(get_db),
    current_user: models.User = Depends(user_is_admin_or_self)
):
    """
    Удаляет настройку автоплатежа из базы данных.
    """
    # 1. Находим платеж и проверяем, что он принадлежит пользователю
    payment_to_delete = db.query(models.ScheduledPayment).filter(
        models.ScheduledPayment.id == payment_id,
        models.ScheduledPayment.user_id == user_id
    ).first()

    if not payment_to_delete:
        raise HTTPException(status_code=404, detail="Scheduled payment not found.")
    
    # 2. Удаляем и сохраняем изменения
    db.delete(payment_to_delete)
    db.commit()

    return {
        "status": "deleted",
        "message": f"Scheduled payment with id {payment_id} has been deleted."
    }