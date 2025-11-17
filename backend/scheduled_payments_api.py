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
    # 1. Находим счет списания и проверяем, что он принадлежит пользователю
    debtor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == payment_data.debtor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()

    # 2. Проверяем, что счет списания найден и валиден
    if not debtor_account:
        raise HTTPException(status_code=404, detail="Debtor account not found or access denied.")
    if not debtor_account.currency:
        raise HTTPException(status_code=400, detail="Debtor account does not have a currency set.")

    # --- vvv НОВАЯ ПРОВЕРКА ЗДЕСЬ vvv ---

    # 3. Находим счет зачисления и проверяем, что он ТОЖЕ принадлежит пользователю
    creditor_account = db.query(models.Account).join(models.ConnectedBank).filter(
        models.Account.id == payment_data.creditor_account_id,
        models.ConnectedBank.user_id == user_id
    ).first()

    # 4. Проверяем, что счет зачисления найден
    if not creditor_account:
        raise HTTPException(status_code=404, detail="Creditor account not found or access denied.")

    # --- ^^^ КОНЕЦ НОВОЙ ПРОВЕРКИ ^^^ ---

    # 5. Получаем словарь из Pydantic модели
    payment_dict = payment_data.model_dump()

    # 6. Добавляем в словарь валюту, полученную из счета списания
    payment_dict['currency'] = debtor_account.currency
    
    # 7. Преобразуем enum из схемы в enum для модели
    schema_enum_value = payment_data.amount_type.value
    model_enum_member = models.ScheduledPaymentAmountType(schema_enum_value)
    payment_dict['amount_type'] = model_enum_member
    
    # 8. Создаем объект модели SQLAlchemy
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
    """
    Обновляет параметры существующего автоплатежа.
    Позволяет изменять любые поля, переданные в теле запроса.
    """
    # 1. Находим платеж в БД и проверяем, что он принадлежит пользователю
    db_payment = db.query(models.ScheduledPayment).filter(
        models.ScheduledPayment.id == payment_id,
        models.ScheduledPayment.user_id == user_id
    ).first()

    if not db_payment:
        raise HTTPException(status_code=404, detail="Scheduled payment not found.")

    # 2. Получаем словарь с данными, которые клиент хочет обновить
    update_dict = update_data.model_dump(exclude_unset=True)

    # 3. Если в обновлении есть amount_type, преобразуем его в enum для модели
    if 'amount_type' in update_dict and update_dict['amount_type'] is not None:
        schema_enum_value = update_data.amount_type.value
        model_enum_member = models.ScheduledPaymentAmountType(schema_enum_value)
        update_dict['amount_type'] = model_enum_member

    # 4. Если меняется счет списания, мы ОБЯЗАНЫ обновить валюту
    if 'debtor_account_id' in update_dict:
        new_debtor_id = update_dict['debtor_account_id']
        new_debtor_account = db.query(models.Account).join(models.ConnectedBank).filter(
            models.Account.id == new_debtor_id,
            models.ConnectedBank.user_id == user_id
        ).first()
        
        if not new_debtor_account:
            raise HTTPException(status_code=404, detail="New debtor account not found or access denied.")
        
        # Обновляем валюту в словаре для апдейта
        update_dict['currency'] = new_debtor_account.currency

    # 5. Применяем обновления к объекту модели
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