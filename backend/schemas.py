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
    bank_name: str
    bank_client_id: str
    consent_type: str = Field(..., example="single_use")
    currency: str = Field(..., example="RUB")
    
    # --- vvv ГЛАВНОЕ ИЗМЕНЕНИЕ ЗДЕСЬ vvv ---
    # Меняем тип с str на Decimal. Pydantic будет автоматически валидировать
    # и преобразовывать входящие данные (числа или строки) в Decimal.
    # Field(...) добавляет валидацию на уровне базы данных для чисел.
    amount: Decimal = Field(..., max_digits=10, decimal_places=2, example=150.50)
    # --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---
    
    debtor_account: str = Field(..., example="40817810000000000001") # Счет списания
    creditor_name: str = Field(..., example="Иванов Иван") # Имя получателя
    creditor_account: str = Field(..., example="40817810000000000002") # Счет получателя
    reference: str = Field(..., example="Оплата услуг") # Назначение платежа

    # Валидатор, который мы добавляли ранее, больше не нужен,
    # так как Pydantic теперь сам управляет типом. Удалите его.


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
    creditor_bank_code: str = Field(..., example="044525225") 
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
class PaymentStatusAmount(BaseModel):
    amount: str
    currency: str

class PaymentStatusData(BaseModel):
    paymentId: str
    status: str
    creationDateTime: datetime
    statusUpdateDateTime: datetime
    instructedAmount: PaymentStatusAmount
    description: Optional[str] = None

class PaymentStatusResponse(BaseModel):
    data: PaymentStatusData

# --- ^^^ КОНЕЦ НОВЫХ СХЕМ ^^^ ---