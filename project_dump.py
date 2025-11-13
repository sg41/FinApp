import os
import argparse
from pathlib import Path

def create_text_dump(source_dir: str, output_file: str, extension: str = ".dart"):
    """
    Создаёт текстовый дамп всех  файлов из проекта.
    Перед содержимым каждого файла добавляется строка с его путём от корня проекта.

    :param source_dir: Путь к корневой директории проекта.
    :param output_file: Путь к выходному текстовому файлу.
    """
    source_path = Path(source_dir).resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Исходная директория не найдена: {source_path}")

    source_files = sorted(source_path.rglob("*"+extension))

    with open(output_file, "w", encoding="utf-8") as out_f:
        for source_file in source_files:
            # Относительный путь от корня проекта
            rel_path = source_file.relative_to(source_path)
            # Заголовок
            out_f.write(f"=== {rel_path} ===\n")
            # Содержимое файла
            try:
                with open(source_file, "r", encoding="utf-8") as src_f:
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
        description="Создаёт текстовый дамп всех исходный файлов проекта в один файл."
    )
    parser.add_argument(
        "source",
        help="Путь к корневой папке проекта"
    )
    parser.add_argument(
        "-o", "--output",
        default="project_dump.txt",
        help="Имя выходного текстового файла (по умолчанию: project_dump.txt)"
    )
    parser.add_argument(
        "-e", "--extension",
        default=".dart",
        help="Расширение исходных кодовых файлов (по умолчанию: .dart)"
    )

    args = parser.parse_args()

    try:
        create_text_dump(args.source, args.output, args.extension)
    except Exception as e:
        print(f"❌ Ошибка: {e}")

if __name__ == "__main__":
    main()