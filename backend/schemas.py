# finance-app-master/schemas.py
from pydantic import BaseModel, field_validator, Field
from typing import Optional, List, Any
from datetime import datetime, date
from decimal import Decimal

class UserCreate(BaseModel):
    email: str
    password: str

    @field_validator('password')
    def password_not_too_long(cls, v):
        if len(v.encode('utf-8')) > 72:
            raise ValueError('Password must be at most 72 bytes long')
        return v


class UserLogin(BaseModel):
    username: str = Field(alias="email")
    password: str

    class Config:
        populate_by_name = True

class Token(BaseModel):
    access_token: str
    token_type: str

class TokenWithUser(Token):
    user_id: int

class UserResponse(BaseModel):
    id: int
    email: str

    class Config:
        from_attributes = True

class UserListResponse(BaseModel):
    count: int
    users: list[UserResponse]


class UserUpdateAdmin(BaseModel):
    email: Optional[str] = None
    is_admin: Optional[bool] = None

# --- НОВЫЕ СХЕМЫ ДЛЯ БАНКОВ ---
class BankResponse(BaseModel):
    id: int
    name: str
    base_url: str
    auto_approve: bool
    icon_url: Optional[str] = None # <-- Оставляем это поле как было
    
    class Config:
        from_attributes = True

class BankListResponse(BaseModel):
    count: int
    banks: list[BankResponse]

class AccountSchema(BaseModel):
    id: int
    connection_id: int
    api_account_id: str
    status: Optional[str] = None
    currency: Optional[str] = None
    account_type: Optional[str] = None
    account_subtype: Optional[str] = None
    nickname: Optional[str] = None
    opening_date: Optional[str] = None
    owner_data: Optional[Any] = None
    balance_data: Optional[Any] = None
    statement_date: Optional[date] = None
    payment_date: Optional[date] = None
    # Поля, которые мы добавим вручную в эндпоинте
    bank_client_id: str
    bank_name: str
    bank_id: int  # <-- ДОБАВЬТЕ ЭТО ПОЛЕ
    
    class Config:
        from_attributes = True

class AccountListResponse(BaseModel):
    count: int
    accounts: List[AccountSchema]

# --- vvv НОВЫЕ СХЕМЫ ДЛЯ ТРАНЗАКЦИЙ vvv ---
class TransactionAmountDetail(BaseModel):
    amount: str
    currency: str

class BankTransactionCodeDetail(BaseModel):
    code: str

class TransactionDetail(BaseModel):
    accountId: str
    transactionId: str
    transactionOinf: Optional[str] = None
    amount: TransactionAmountDetail
    creditDebitIndicator: str
    status: str
    bookingDateTime: datetime
    valueDateTime: datetime
    transactionInformation: Optional[str] = None
    bankTransactionCode: Optional[BankTransactionCodeDetail] = None
    code: Optional[str] = None

class TransactionListData(BaseModel):
    transaction: List[TransactionDetail]

class TransactionListResponse(BaseModel):
    data: TransactionListData
# --- ^^^ КОНЕЦ НОВЫХ СХЕМ ^^^ ---

# --- vvv НОВЫЕ СХЕМЫ ДЛЯ СОГЛАСИЙ НА ПЛАТЕЖИ vvv ---
class PaymentConsentInitiate(BaseModel):
    # Обязательные поля для любого типа согласия
    bank_name: str
    # vvv ИЗМЕНЕНИЕ: Переименовываем поле, чтобы оно соответствовало API банка vvv
    client_id: str = Field(..., description="ID клиента в банке")
    # ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^
    consent_type: str = Field(..., description="Тип согласия: 'single_use', 'multi_use', 'vrp'")
    debtor_account: str = Field(..., description="Счет списания")
    currency: str = Field("RUB", description="Валюта")
    
    # ... (остальные поля без изменений) ...
    amount: Optional[Decimal] = Field(None, max_digits=10, decimal_places=2, description="Сумма для одноразового платежа")
    creditor_name: Optional[str] = Field(None, description="Имя получателя")
    creditor_account: Optional[str] = Field(None, description="Счет получателя")
    max_uses: Optional[int] = Field(None, description="Макс. количество использований")
    max_amount_per_payment: Optional[Decimal] = Field(None, max_digits=10, decimal_places=2, description="Макс. сумма одного платежа")
    max_total_amount: Optional[Decimal] = Field(None, max_digits=10, decimal_places=2, description="Общий лимит по сумме")
    allowed_creditor_accounts: Optional[List[str]] = Field(None, description="Список разрешенных счетов получателей")
    valid_until: Optional[datetime] = Field(None, description="Действителен до")
    vrp_max_individual_amount: Optional[Decimal] = Field(None, max_digits=10, decimal_places=2, description="VRP: Макс. сумма одного платежа")
    vrp_daily_limit: Optional[Decimal] = Field(None, max_digits=10, decimal_places=2, description="VRP: Дневной лимит")
    vrp_monthly_limit: Optional[Decimal] = Field(None, max_digits=10, decimal_places=2, description="VRP: Месячный лимит")
    reference: Optional[str] = Field(None, description="Назначение платежа")


class PaymentConsentResponse(BaseModel):
    id: int
    user_id: int
    bank_name: str
    status: str
    consent_id: Optional[str] = None
    details: Optional[Any] = None

    class Config:
        from_attributes = True

class PaymentConsentListResponse(BaseModel):
    count: int
    consents: List[PaymentConsentResponse]
# --- ^^^ КОНЕЦ НОВЫХ СХЕМ ^^^ ---

class TurnoverResponse(BaseModel):
    account_id: str
    total_credit: Decimal = Field(..., description="Общая сумма поступлений (приход)")
    total_debit: Decimal = Field(..., description="Общая сумма списаний (расход)")
    currency: str
    period_from: Optional[datetime] = None
    period_to: Optional[datetime] = None

class AccountUpdate(BaseModel):
    statement_date: Optional[date] = None
    payment_date: Optional[date] = None

# --- vvv НОВЫЕ СХЕМЫ ДЛЯ ПЛАТЕЖЕЙ vvv ---

# Схема для ответа от API банка при создании платежа
class BankPaymentData(BaseModel):
    paymentId: str
    status: str
    creationDateTime: datetime


class BankPaymentResponse(BaseModel):
    data: BankPaymentData


# Схема для инициации внешнего платежа
class PaymentInitiate(BaseModel):
    payment_consent_id: int = Field(..., description="ID нашего согласия на платеж в БД")
    debtor_account_id: int = Field(..., description="ID счета списания в нашей БД")
    creditor_name: str = Field(..., example="Иванов Иван")
    creditor_account: str = Field(..., example="40817810000000000002")
    # vvv ИЗМЕНЕНИЕ ЗДЕСЬ vvv
    creditor_bank_code: str = Field(..., description="Символьный код банка получателя (например, 'abank')", example="abank") 
    # ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^
    amount: Decimal = Field(..., max_digits=10, decimal_places=2, example=150.50)
    currency: str = Field(..., example="RUB")
    reference: str = Field(..., example="Оплата услуг")

# Схема для инициации перевода между своими счетами
class InternalTransferInitiate(BaseModel):
    payment_consent_id: int = Field(..., description="ID нашего согласия на платеж в БД")
    debtor_account_id: int = Field(..., description="ID счета списания в нашей БД")
    creditor_account_id: int = Field(..., description="ID счета зачисления в нашей БД")
    amount: Decimal = Field(..., max_digits=10, decimal_places=2, example=1000.00)
    currency: str = Field(..., example="RUB")
    reference: Optional[str] = "Перевод между своими счетами"
    
# Схемы для получения статуса платежа
class PaymentStatusData(BaseModel):
    paymentId: str
    status: str
    creationDateTime: datetime
    statusUpdateDateTime: datetime
    # Заменяем вложенный объект на два плоских поля
    amount: str
    currency: str
    description: Optional[str] = None

class PaymentStatusResponse(BaseModel):
    data: PaymentStatusData

# --- ^^^ КОНЕЦ НОВЫХ СХЕМ ^^^ ---

# --- vvv НОВЫЕ СХЕМЫ ДЛЯ ИСТОРИИ ПЛАТЕЖЕЙ vvv ---
class PaymentResponse(BaseModel):
    id: int
    user_id: int
    debtor_account_id: int
    consent_id: int
    bank_payment_id: str
    status: str
    amount: Decimal
    currency: str
    creditor_details: Any
    created_at: datetime
    updated_at: Optional[datetime] = None

    class Config:
        from_attributes = True

class PaymentListResponse(BaseModel):
    count: int
    payments: List[PaymentResponse]
# --- ^^^ КОНЕЦ НОВЫХ СХЕМ ^^^ ---