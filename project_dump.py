import argparse
from pathlib import Path
import re

def parse_gitignore(gitignore_path: Path):
    """Парсит .gitignore и возвращает список шаблонов (ограниченный синтаксис)."""
    patterns = []
    with open(gitignore_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#") and not line.startswith("!"):
                # Простой случай: игнорируем шаблон
                patterns.append(line)
    return patterns


def is_ignored_by_gitignore(rel_path: Path, patterns):
    """Проверяет, соответствует ли путь одному из шаблонов .gitignore."""
    rel_str = rel_path.as_posix()
    for pat in patterns:
        # Простая проверка: поддержка *, **, /
        if "*" in pat:
            # Заменяем * на [^/]*, ** на .*
            import fnmatch
            if fnmatch.fnmatch(rel_str, pat) or fnmatch.fnmatch(rel_str, pat.rstrip('/') + '/**'):
                return True
        elif pat.endswith('/'):
            # Папка
            if rel_str.startswith(pat.lstrip('/')):
                return True
        else:
            if fnmatch.fnmatch(rel_str, pat):
                return True
            if fnmatch.fnmatch(rel_str, pat.rstrip('/') + '/**'):
                return True
    return False


def is_text_file(file_path: Path, sample_size: int = 1024) -> bool:
    """Проверяет, является ли файл текстовым (UTF-8)."""
    try:
        with open(file_path, 'rb') as f:
            sample = f.read(sample_size)
        sample.decode('utf-8')
        return True
    except (UnicodeDecodeError, OSError, ValueError):
        return False


def create_text_dump(source_dir: str, output_file: str, extension: str = None, regex: str = None, text_only: bool = False):
    source_path = Path(source_dir).resolve()
    if not source_path.exists():
        raise FileNotFoundError(f"Исходная директория не найдена: {source_path}")

    # Загружаем .gitignore, если включён text-only
    gitignore_patterns = []
    if text_only:
        gitignore_path = source_path / ".gitignore"
        if gitignore_path.exists():
            gitignore_patterns = parse_gitignore(gitignore_path)

    # Собираем все файлы
    all_files = [f for f in source_path.rglob("*") if f.is_file()]

    if text_only:
        filtered_files = []
        for f in all_files:
            rel_path = f.relative_to(source_path)

            # Пропускаем, если совпадает с .gitignore
            if gitignore_patterns and is_ignored_by_gitignore(rel_path, gitignore_patterns):
                continue

            # Проверяем, текстовый ли файл
            if is_text_file(f):
                filtered_files.append(f)
    else:
        # Старая логика: фильтрация по имени
        if regex is not None:
            try:
                pattern = re.compile(regex)
            except re.error as e:
                raise ValueError(f"Некорректное регулярное выражение: {e}")
        else:
            if extension is None:
                extension = ".dart"
            escaped_ext = re.escape(extension)
            pattern = re.compile(escaped_ext + r"$")
        filtered_files = [f for f in all_files if pattern.search(f.name)]

    filtered_files = sorted(filtered_files)

    # Запись дампа
    with open(output_file, "w", encoding="utf-8") as out_f:
        for source_file in filtered_files:
            rel_path = source_file.relative_to(source_path)
            out_f.write(f"=== {rel_path} ===\n")
            try:
                with open(source_file, "r", encoding="utf-8") as src_f:
                    content = src_f.read()
            except (UnicodeDecodeError, OSError):
                content = "// [Файл не может быть прочитан как текст]\n"
            out_f.write(content)
            if not content.endswith("\n"):
                out_f.write("\n")
            out_f.write("\n")

    print(f"✅ Текстовый дамп создан: {Path(output_file).resolve()}")


def main():
    parser = argparse.ArgumentParser(
        description="Создаёт текстовый дамп всех исходных файлов проекта в один файл."
    )
    parser.add_argument("source", help="Путь к корневой папке проекта")
    parser.add_argument(
        "-o", "--output",
        default="project_dump.txt",
        help="Имя выходного текстового файла (по умолчанию: project_dump.txt)"
    )
    parser.add_argument(
        "-e", "--extension",
        default=None,
        help="Простое расширение файлов, например '.yaml' или '.js' (по умолчанию: '.dart')"
    )
    parser.add_argument(
        "-r", "--regex",
        default=None,
        metavar="PATTERN",
        help="Регулярное выражение для имени файла (например: '\\.ya?ml$'). Имеет приоритет над --extension."
    )
    parser.add_argument(
        "--text-only",
        action="store_true",
        help="Дампить все текстовые файлы (UTF-8), независимо от расширения. "
             "Игнорирует --extension и --regex. Учитывает .gitignore, если он существует."
    )

    args = parser.parse_args()

    if args.text_only and (args.extension or args.regex):
        parser.error("--text-only нельзя использовать вместе с --extension или --regex")

    try:
        create_text_dump(
            source_dir=args.source,
            output_file=args.output,
            extension=args.extension,
            regex=args.regex,
            text_only=args.text_only
        )
    except Exception as e:
        print(f"❌ Ошибка: {e}")


if __name__ == "__main__":
    main()