FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1

WORKDIR /srv

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY app ./app

# Непривилегированный пользователь: контейнеру нечего делать под root,
# а ключ Snowflake монтируется снаружи только на чтение.
RUN useradd --create-home --uid 10001 copilot && chown -R copilot:copilot /srv
USER copilot

CMD ["uvicorn", "app.api:app", "--host", "0.0.0.0", "--port", "8770"]
