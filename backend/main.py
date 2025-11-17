# finance-app-master/main.py
from fastapi import FastAPI
from fastapi.staticfiles import StaticFiles
from fastapi.middleware.cors import CORSMiddleware
from dotenv import load_dotenv

import models
from database import engine
from auth import router as auth_router
from user_api import router as user_router
from banks_api import router as banks_router
from connections_api import router as connections_router
from accounts_api import router as accounts_router
from transactions_api import router as transactions_router 
from payment_consents_api import router as payment_consents_router
from payments_api import router as payments_router # <--- ДОБАВЛЕН ИМПОРТ
from scheduled_payments_api import router as scheduled_payments_router # <--- НОВЫЙ ИМПОРТ

load_dotenv()

# models.Base.metadata.create_all(bind=engine)

app = FastAPI(
    title="FinApp API",
    version="1.0.0",
    description="API для подключения банковских счетов и управления финансовыми данными."
)

app.mount("/static", StaticFiles(directory="static"), name="static")

origins = [
    "*",
]

app.add_middleware(
    CORSMiddleware,
    allow_origins=origins,
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(auth_router)
app.include_router(user_router)
app.include_router(connections_router)
app.include_router(banks_router)
app.include_router(accounts_router)
app.include_router(transactions_router)
app.include_router(payment_consents_router)
app.include_router(payments_router) # <--- ПОДКЛЮЧЕН НОВЫЙ РОУТЕР
app.include_router(scheduled_payments_router) # <--- ПОДКЛЮЧИТЬ НОВЫЙ РОУТЕР