from fastapi import APIRouter, Depends, HTTPException, Query
from sqlalchemy.orm import Session
from typing import List, Optional
from database import get_db
import models
from pydantic import BaseModel
from utils import revoke_bank_consent  # <-- новый импорт
import asyncio


# --- Схемы (Pydantic модели) ---
class UserCreate(BaseModel):
    email: str

class UserResponse(BaseModel):
    id: int
    email: str

    class Config:
        from_attributes = True  # Pydantic v2 (для v1: orm_mode = True)

class UserListResponse(BaseModel):
    count: int
    users: List[UserResponse]


# --- Роутер ---
router = APIRouter(
    prefix="/users",
    tags=["users"]
)


@router.post("/", response_model=UserResponse, summary="Создать нового пользователя")
def create_user(user: UserCreate, db: Session = Depends(get_db)):
    existing_user = db.query(models.User).filter(models.User.email == user.email).first()
    if existing_user:
        raise HTTPException(status_code=400, detail="User with this email already exists")
    
    db_user = models.User(email=user.email)
    db.add(db_user)
    db.commit()
    db.refresh(db_user)
    return db_user


@router.get("/", response_model=UserListResponse, summary="Получить список пользователей")
def get_users(
    user_id: Optional[List[int]] = Query(None, description="Фильтр по ID пользователей. Можно указать несколько: ?user_id=1&user_id=2"),
    db: Session = Depends(get_db)
):
    """
    Возвращает список пользователей.
    Можно отфильтровать по одному или нескольким ID через query-параметр `user_id`.
    """
    query = db.query(models.User)
    
    if user_id:
        query = query.filter(models.User.id.in_(user_id))
    
    users = query.all()
    
    if user_id and not users:
        raise HTTPException(status_code=404, detail="No users found with the provided ID(s)")
    
    return UserListResponse(count=len(users), users=users)

@router.put("/{user_id}", response_model=UserResponse, summary="Обновить email пользователя")
def update_user(user_id: int, user: UserCreate, db: Session = Depends(get_db)):
    db_user = db.query(models.User).filter(models.User.id == user_id).first()
    if not db_user:
        raise HTTPException(status_code=404, detail="User not found")
    
    if db_user.email != user.email:
        existing = db.query(models.User).filter(models.User.email == user.email).first()
        if existing:
            raise HTTPException(status_code=400, detail="Email already in use")
    
    db_user.email = user.email
    db.commit()
    db.refresh(db_user)
    return db_user


# @router.delete("/{user_id}", summary="Удалить пользователя и все его подключения")
# def delete_user(user_id: int, db: Session = Depends(get_db)):
#     user = db.query(models.User).filter(models.User.id == user_id).first()
#     if not user:
#         raise HTTPException(status_code=404, detail="User not found")
    
#     # Удаляем связанные подключения (если каскад не настроен в модели)
#     db.query(models.ConnectedBank).filter(models.ConnectedBank.user_id == user_id).delete()
    
#     db.delete(user)
#     db.commit()
#     return {"status": "deleted", "message": f"User {user_id} and all connections deleted"}

@router.delete("/{user_id}", summary="Удалить пользователя и все его подключения")
async def delete_user(user_id: int, db: Session = Depends(get_db)):
    user = db.query(models.User).filter(models.User.id == user_id).first()
    if not user:
        raise HTTPException(status_code=404, detail="User not found")
    
    # Получаем все подключения
    connections = db.query(models.ConnectedBank).filter(models.ConnectedBank.user_id == user_id).all()
    
    # Отзываем все согласия параллельно (асинхронно)
    await asyncio.gather(*[revoke_bank_consent(conn) for conn in connections])
    
    # Удаляем из БД
    for conn in connections:
        db.delete(conn)
    db.delete(user)
    db.commit()
    
    return {"status": "deleted", "message": f"User {user_id} and all connections deleted"}