# Ответ на тестовое задание

| Файл | Что это |
|------|---------|
| `test-assignment-answer-en.pdf` | Ответ на Parts 1–5, английская версия — подача, 16 страниц |
| `test-assignment-answer-en.html` | Исходник английской версии |
| `test-assignment-answer-ru.pdf` | Русская версия, 16 страниц |
| `test-assignment-answer-ru.html` | Исходник русской версии |

Все цифры в документе — замеры из песочницы `../snowflake-sandbox/`, а не оценки.
Каждое утверждение проверяется запросом; список запросов — в разделе
«Приложение: воспроизводимость».

## Сборка PDF

Локального pandoc и weasyprint в окружении нет, зато есть headless Chromium
и кириллические шрифты (Liberation Sans, DejaVu):

```bash
/opt/pw-browsers/chromium-1194/chrome-linux/chrome --headless --disable-gpu --no-sandbox \
  --no-pdf-header-footer --print-to-pdf=test-assignment-answer-ru.pdf \
  file://$PWD/test-assignment-answer-ru.html
```

## Статус

Задание требует подачи на английском — подаётся `test-assignment-answer-en.pdf`.
Русская версия ведётся параллельно, для внутреннего просмотра; содержание идентично.
При правке любой из версий синхронизировать обе.
