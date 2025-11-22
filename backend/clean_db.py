from database import engine
from sqlalchemy import text

def clean_database():
    with engine.connect() as connection:
        print("Очистка базы данных...")
        # Удаляем таблицу версий Alembic
        connection.execute(text("DROP TABLE IF EXISTS alembic_version;"))
        
        # Удаляем ваши таблицы (порядок важен из-за связей)
        connection.execute(text("DROP TABLE IF EXISTS scheduled_payments CASCADE;"))
        connection.execute(text("DROP TABLE IF EXISTS payments CASCADE;"))
        connection.execute(text("DROP TABLE IF EXISTS payment_consents CASCADE;"))
        connection.execute(text("DROP TABLE IF EXISTS accounts CASCADE;"))
        connection.execute(text("DROP TABLE IF EXISTS connected_banks CASCADE;"))
        connection.execute(text("DROP TABLE IF EXISTS banks CASCADE;"))
        connection.execute(text("DROP TABLE IF EXISTS users CASCADE;"))
        
        connection.commit()
        print("База данных полностью очищена.")

if __name__ == "__main__":
    clean_database()