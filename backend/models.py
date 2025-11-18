# finance-app-master/models.py
import enum
from sqlalchemy import Column, Integer, String, Boolean, Numeric, Enum, ForeignKey, DateTime, Date
from sqlalchemy.orm import relationship, column_property
from sqlalchemy.dialects.postgresql import JSONB 
from sqlalchemy.sql import func 
from database import Base
from sqlalchemy.ext.associationproxy import association_proxy
from sqlalchemy.sql import select

class Bank(Base):
    __tablename__ = "banks"
    id = Column(Integer, primary_key=True, index=True)
    name = Column(String, unique=True, index=True, nullable=False)
    client_id = Column(String, nullable=False)
    client_secret = Column(String, nullable=False)
    base_url = Column(String, nullable=False)
    auto_approve = Column(Boolean, default=False)
    icon_filename = Column(String, nullable=True)

class User(Base):
    __tablename__ = "users"
    id = Column(Integer, primary_key=True, index=True)
    email = Column(String, unique=True, index=True)
    hashed_password = Column(String)
    is_admin = Column(Boolean, default=False, server_default='f')
    
class ConnectedBank(Base):
    __tablename__ = "connected_banks"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"))
    bank_name = Column(String, index=True)
    bank_client_id = Column(String, index=True)
    request_id = Column(String, unique=True, nullable=True, index=True)
    consent_id = Column(String, unique=True, nullable=True)
    status = Column(String, default="awaitingauthorization")
    full_name = Column(String, nullable=True)
    
    user = relationship("User")
    accounts = relationship("Account", back_populates="connection", cascade="all, delete-orphan")

class Account(Base):
    __tablename__ = "accounts"
    id = Column(Integer, primary_key=True, index=True)
    connection_id = Column(Integer, ForeignKey("connected_banks.id"), nullable=False)
    
    api_account_id = Column(String, index=True, nullable=False)
    status = Column(String)
    currency = Column(String(3))
    account_type = Column(String) 
    account_subtype = Column(String) 
    nickname = Column(String)
    opening_date = Column(String, nullable=True)
    
    statement_date = Column(Date, nullable=True)
    payment_date = Column(Date, nullable=True)

    owner_data = Column(JSONB, nullable=True)
    balance_data = Column(JSONB, nullable=True)

    connection = relationship("ConnectedBank", back_populates="accounts")
    
    bank_name = association_proxy("connection", "bank_name")
    bank_client_id = association_proxy("connection", "bank_client_id")
    bank_id = column_property(
        select(Bank.id)
        .join(ConnectedBank, Bank.name == ConnectedBank.bank_name)
        .where(ConnectedBank.id == connection_id)
        .correlate_except(Bank)
        .scalar_subquery()
    )

class PaymentConsent(Base):
    __tablename__ = "payment_consents"
    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    bank_name = Column(String, index=True)
    bank_client_id = Column(String, index=True)
    
    request_id = Column(String, unique=True, nullable=True, index=True)
    consent_id = Column(String, unique=True, nullable=True)
    
    status = Column(String, default="awaitingauthorization")
    
    details = Column(JSONB, nullable=True)

    user = relationship("User")
    # --- vvv НЕДОСТАЮЩАЯ СТРОКА ДОБАВЛЕНА ЗДЕСЬ vvv ---
    payments = relationship("Payment", back_populates="consent", cascade="all, delete-orphan")
    # --- ^^^ КОНЕЦ ИЗМЕНЕНИЯ ^^^ ---


class Payment(Base):
    __tablename__ = "payments"
    id = Column(Integer, primary_key=True, index=True)
    
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    debtor_account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False)
    
    consent_id = Column(Integer, ForeignKey("payment_consents.id"), nullable=False)
    
    bank_payment_id = Column(String, index=True, nullable=False)
    bank_name = Column(String, nullable=False)
    bank_client_id = Column(String, nullable=False)
    status = Column(String, default="pending")
    
    amount = Column(Numeric(10, 2), nullable=False)
    currency = Column(String(3), nullable=False)
    
    creditor_details = Column(JSONB)
    
    idempotency_key = Column(String, unique=True, nullable=False)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    user = relationship("User")
    debtor_account = relationship("Account")
    consent = relationship("PaymentConsent", back_populates="payments")

# Добавляем Enum для типа суммы
class ScheduledPaymentAmountType(enum.Enum):
    FIXED = "fixed"                  # Фиксированная сумма
    TOTAL_DEBIT = "total_debit"      # Все расходы за период
    NET_DEBIT = "net_debit"          # Разница между расходами и доходами
    MINIMUM_PAYMENT = "minimum_payment" # <-- НОВОЕ ЗНАЧЕНИЕ

class ScheduledPayment(Base):
    __tablename__ = "scheduled_payments"

    id = Column(Integer, primary_key=True, index=True)
    user_id = Column(Integer, ForeignKey("users.id"), nullable=False)
    
    debtor_account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False) 
    creditor_account_id = Column(Integer, ForeignKey("accounts.id"), nullable=False) 

    payment_day_of_month = Column(Integer, nullable=False)
    statement_day_of_month = Column(Integer, nullable=False)

    amount_type = Column(Enum(ScheduledPaymentAmountType), nullable=False)
    fixed_amount = Column(Numeric(10, 2), nullable=True)
    currency = Column(String(3), nullable=True)
    
    # vvv НОВОЕ ПОЛЕ vvv
    minimum_payment_percentage = Column(Numeric(5, 2), nullable=True) # Например, 10.50 (%)
    # ^^^ КОНЕЦ НОВОГО ПОЛЯ ^^^

    is_active = Column(Boolean, default=True, nullable=False)

    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

    # ... (отношения) ...
    user = relationship("User")
    debtor_account = relationship("Account", foreign_keys=[debtor_account_id])
    creditor_account = relationship("Account", foreign_keys=[creditor_account_id])