# user_api.py
from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
import models
from database import get_db
from models import User
from schemas import UserResponse, UserListResponse, UserCreate
from deps import get_current_user  # ← новая зависимость

router = APIRouter(prefix="/users", tags=["users"])


@router.get("/", response_model=UserListResponse, summary="Get Users (public)")
def get_users(
    email: Optional[str] = Query(None, description="Filter users by email (exact match)"),
    db: Session = Depends(get_db)
):
    """
    Получить список пользователей. Доступен без авторизации.
    Можно отфильтровать по email (точное совпадение).
    Пример: /users?email=user@example.com
    """
    query = db.query(User)
    
    if email:
        query = query.filter(User.email == email)
    
    users = query.all()
    return UserListResponse(count=len(users), users=users)

@router.put("/me", response_model=UserResponse)
def update_my_email(
    user: UserCreate,
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Проверка уникальности email
    if user.email != current_user.email:
        existing = db.query(User).filter(User.email == user.email).first()
        if existing:
            raise HTTPException(status_code=400, detail="Email already in use")
        current_user.email = user.email
        db.commit()
        db.refresh(current_user)
    return current_user


@router.delete("/me")
def delete_my_account(
    db: Session = Depends(get_db),
    current_user: User = Depends(get_current_user)
):
    # Здесь можно вызвать revoke_bank_consent для всех подключений
    from utils import revoke_bank_consent
    import asyncio
    connections = db.query(models.ConnectedBank).filter(models.ConnectedBank.user_id == current_user.id).all()
    asyncio.run(asyncio.gather(*[revoke_bank_consent(conn) for conn in connections]))
    
    db.query(models.ConnectedBank).filter(models.ConnectedBank.user_id == current_user.id).delete()
    db.delete(current_user)
    db.commit()
    return {"status": "deleted", "message": "Your account has been deleted"}