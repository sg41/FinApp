import os
import argparse
from pathlib import Path

def create_text_dump(source_dir: str, output_file: str):
    """
    Создаёт текстовый дамп всех .dart файлов из Flutter-проекта.
    Перед содержимым каждого файла добавляется строка с его путём от корня проекта.

    :param source_dir: Путь к корневой директории Flutter-проекта.
    :param output_file: Путь к выходному текстовому файлу.
    """
    source_path = Path(source_dir).resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Исходная директория не найдена: {source_path}")

    dart_files = sorted(source_path.rglob("*.dart"))

    with open(output_file, "w", encoding="utf-8") as out_f:
        for dart_file in dart_files:
            # Относительный путь от корня проекта
            rel_path = dart_file.relative_to(source_path)
            # Заголовок
            out_f.write(f"=== {rel_path} ===\n")
            # Содержимое файла
            try:
                with open(dart_file, "r", encoding="utf-8") as src_f:
                    content = src_f.read()
            except UnicodeDecodeError:
                # Пропускаем бинарные или повреждённые файлы
                content = "// [Файл не может быть прочитан как текст]\n"
            out_f.write(content)
            # Гарантируем пустую строку в конце файла для читаемости
            if not content.endswith("\n"):
                out_f.write("\n")
            out_f.write("\n")

    print(f"✅ Текстовый дамп создан: {Path(output_file).resolve()}")

def main():
    parser = argparse.ArgumentParser(
        description="Создаёт текстовый дамп всех .dart файлов Flutter-проекта в один файл."
    )
    parser.add_argument(
        "source",
        help="Путь к корневой папке Flutter-проекта"
    )
    parser.add_argument(
        "-o", "--output",
        default="flutter_dump.txt",
        help="Имя выходного текстового файла (по умолчанию: flutter_dump.txt)"
    )

    args = parser.parse_args()

    try:
        create_text_dump(args.source, args.output)
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    main()