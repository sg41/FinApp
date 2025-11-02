# encryption_service.py
import os
from dotenv import load_dotenv
from cryptography.fernet import Fernet

load_dotenv()

# Загружаем ключ из .env файла. Он должен быть в формате bytes.
key_str = os.getenv("ENCRYPTION_KEY")
if not key_str:
    raise ValueError("ENCRYPTION_KEY не найден в .env файле!")
key = key_str.encode()

fernet = Fernet(key)

def encrypt_data(data: str) -> bytes:
    """Шифрует строку и возвращает байты."""
    return fernet.encrypt(data.encode())

def decrypt_data(encrypted_data: bytes) -> str:
    """Дешифрует байты и возвращает строку."""
    return fernet.decrypt(encrypted_data).decode()