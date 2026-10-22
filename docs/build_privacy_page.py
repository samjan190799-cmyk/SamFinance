"""Собирает docs/privacy/index.html из Resources/Legal/PrivacyPolicy.{ru,en}.md.

Запуск из корня репозитория: python docs/build_privacy_page.py
Те же Markdown-файлы показываются внутри приложения (Настройки → Политика конфиденциальности),
поэтому текст правят только в них, а страницу пересобирают этим скриптом.
"""
import html
import os
import re

root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
legal = os.path.join(root, 'Resources', 'Legal')
out_dir = os.path.join(root, 'docs', 'privacy')

BOLD = re.compile(r'\*\*(.+?)\*\*')
LINK = re.compile(r'\[([^\]]+)\]\((https://[^)\s]+)\)')


def inline(text):
    text = html.escape(text, quote=False)
    text = BOLD.sub(r'<strong>\1</strong>', text)
    return LINK.sub(r'<a href="\2" rel="noopener">\1</a>', text)


def render(markdown):
    parts = []
    paragraph = []
    in_list = False

    def flush_paragraph():
        if paragraph:
            parts.append('<p>' + inline(' '.join(paragraph)) + '</p>')
            paragraph.clear()

    def close_list():
        nonlocal in_list
        if in_list:
            parts.append('</ul>')
            in_list = False

    for raw in markdown.splitlines():
        line = raw.strip()
        if not line:
            flush_paragraph()
            close_list()
        elif line.startswith('## '):
            flush_paragraph()
            close_list()
            parts.append('<h3>' + inline(line[3:]) + '</h3>')
        elif line.startswith('# '):
            flush_paragraph()
            close_list()
            parts.append('<h2>' + inline(line[2:]) + '</h2>')
        elif line.startswith('- '):
            flush_paragraph()
            if not in_list:
                parts.append('<ul>')
                in_list = True
            parts.append('<li>' + inline(line[2:]) + '</li>')
        else:
            close_list()
            paragraph.append(line)
    flush_paragraph()
    close_list()
    return '\n'.join(parts)


def read(name):
    with open(os.path.join(legal, name), encoding='utf-8') as f:
        return f.read()


PAGE = '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Hashiv: Privacy Policy / Политика конфиденциальности</title>
<style>
  :root { color-scheme: light dark; --bg: #ffffff; --fg: #1c1d21; --muted: #5a5c63; --accent: #4b6a00; --line: #e3e4e8; }
  @media (prefers-color-scheme: dark) { :root { --bg: #111214; --fg: #f4f4f5; --muted: #9b9da4; --accent: #c6f432; --line: #26272c; } }
  body { margin: 0; background: var(--bg); color: var(--fg); font: 16px/1.6 -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif; }
  main { max-width: 720px; margin: 0 auto; padding: 24px 20px 64px; }
  nav { display: flex; gap: 12px; padding-bottom: 16px; border-bottom: 1px solid var(--line); }
  nav a { color: var(--accent); font-weight: 600; text-decoration: none; padding: 6px 14px; border: 1px solid var(--line); border-radius: 999px; }
  h2 { font-size: 28px; margin: 32px 0 4px; }
  h3 { font-size: 18px; margin: 28px 0 6px; }
  p, li { color: var(--muted); }
  strong { color: var(--fg); }
  a { color: var(--accent); }
  section { padding-top: 8px; }
  section + section { margin-top: 56px; border-top: 1px solid var(--line); }
</style>
</head>
<body>
<main>
<nav><a href="#en">English</a><a href="#ru">Русский</a></nav>
<section id="en" lang="en">
{en}
</section>
<section id="ru" lang="ru">
{ru}
</section>
</main>
</body>
</html>
'''

os.makedirs(out_dir, exist_ok=True)
with open(os.path.join(out_dir, 'index.html'), 'w', encoding='utf-8', newline='\n') as f:
    f.write(PAGE.replace('{en}', render(read('PrivacyPolicy.en.md'))).replace('{ru}', render(read('PrivacyPolicy.ru.md'))))
print('docs/privacy/index.html собран')
