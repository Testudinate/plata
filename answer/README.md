# Ответ на тестовое задание

| Файл | Что это |
|------|---------|
| `test-assignment-answer-ru.pdf` | Ответ на Parts 1–5, русская версия, 9 страниц |
| `test-assignment-answer-ru.html` | Исходник документа |

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

Русская версия — для внутреннего просмотра. Задание требует подачи на английском:
англоязычная версия ещё не сделана.
