# auth.py
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from jose import JWTError
from starlette.requests import Request
from urllib.parse import unquote

from database import get_db
from models import User
from security import verify_password, create_access_token, ACCESS_TOKEN_EXPIRE_MINUTES, get_password_hash
from schemas import UserLogin, Token, UserCreate,UserResponse
from datetime import timedelta
from utils import log_request, logger

router = APIRouter(prefix="/auth", tags=["auth"])


def authenticate_user(db: Session, email: str, password: str):
    user = db.query(User).filter(User.email == email).first()
    if not user or not verify_password(password, user.hashed_password):
        return False
    return user


@router.post("/register", response_model=UserResponse)
def register(user: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(User).filter(User.email == user.email).first()
    if db_user:
        raise HTTPException(status_code=400, detail="Email already registered")
    hashed_pw = get_password_hash(user.password)
    new_user = User(email=user.email, hashed_password=hashed_pw)
    db.add(new_user)
    db.commit()
    db.refresh(new_user)
    return new_user

@router.post("/login", response_model=UserLogin)
async def login(
    request: Request,  # ← добавили
    form_data: OAuth2PasswordRequestForm = Depends(),
    db: Session = Depends(get_db)
):
    # 1. Показать сырое тело
    raw_body = await request.body()
    print("📤 Raw request body:", raw_body.decode('utf-8'))

    # 2. Показать значения из form_data
    email = form_data.username
    password = form_data.password  # ← БЕЗ unquote!

    print("📧 Email (repr):", repr(email))
    print("🔑 Password (repr):", repr(password))
    print("🔑 Password length:", len(password))

    user_obj = authenticate_user(db, email, password)
    if not user_obj:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect email or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
    
    access_token_expires = timedelta(minutes=ACCESS_TOKEN_EXPIRE_MINUTES)
    access_token = create_access_token(
        data={"sub": user_obj.email}, expires_delta=access_token_expires
    )
    return {"access_token": access_token, "token_type": "bearer"}