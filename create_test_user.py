# create_test_user.py
import sys
from sqlalchemy.orm import Session
import models
from database import SessionLocal, engine
from security import get_password_hash # <-- Импортируем хешер паролей

def reset_database():
    """
    Полностью удаляет все таблицы и создает их заново,
    а затем добавляет одного тестового пользователя и одного администратора.
    """
    # --- Блок безопасности ---
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    print("!! ВНИМАНИЕ: Этот скрипт ПОЛНОСТЬЮ УНИЧТОЖИТ все данные !!")
    print("!! в таблицах (users, connected_banks) и создаст их заново. !!")
    print("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")
    
    confirmation = input("Вы уверены, что хотите продолжить? (y/n): ")
    if confirmation.lower() != 'y':
        print("Операция отменена.")
        sys.exit() # Выходим из скрипта

    print("\nНачинаем процесс сброса базы данных...")
    
    db: Session = SessionLocal()
    
    try:
        # 1. Удаление всех таблиц
        print("-> Удаляю старые таблицы...")
        models.Base.metadata.drop_all(bind=engine)
        print("   ...старые таблицы успешно удалены.")

        # 2. Создание всех таблиц заново
        print("-> Создаю новые таблицы...")
        models.Base.metadata.create_all(bind=engine)
        print("   ...новые таблицы успешно созданы.")

        # 3. Создание ОБЫЧНОГО тестового пользователя
        print("-> Создаю обычного тестового пользователя (ID=1)...")
        hashed_pw_user = get_password_hash("password")
        new_user = models.User(
            email="testuser@example.com",
            hashed_password=hashed_pw_user,
            is_admin=False
        )
        db.add(new_user)
        print("   ...обычный пользователь 'testuser@example.com' (пароль: 'password') успешно создан!")
        
        # 4. Создание пользователя-АДМИНИСТРАТОРА
        print("-> Создаю пользователя-администратора (ID=2)...")
        hashed_pw_admin = get_password_hash("adminpass") # Используем другой пароль для админа
        new_admin = models.User(
            email="admin@example.com",
            hashed_password=hashed_pw_admin,
            is_admin=True # <-- УСТАНАВЛИВАЕМ ПРАВА АДМИНИСТРАТОРА
        )
        db.add(new_admin)
        print("   ...администратор 'admin@example.com' (пароль: 'adminpass') успешно создан!")
        
        # Коммитим все изменения (обоих пользователей)
        db.commit()
        
        print("\nПроцесс сброса и инициализации базы данных успешно завершен!")

    except Exception as e:
        print(f"\nПроизошла ошибка во время сброса базы данных: {e}")
        db.rollback()
    finally:
        db.close()

if __name__ == "__main__":
    reset_database()