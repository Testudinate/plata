#!/usr/bin/env bash
# Приёмка стека на VPS: секреты, контейнеры, API, связь со Snowflake, бот.
#
# Тот же принцип, что у check_mcp.sh в hermes-memory: недоступное отсюда
# помечается WARN, а не выдаётся за успех. Exit 2, если есть хоть один FAIL.
#
# Запуск:  bash check_all.sh
# Из каталога agent-service.

set -uo pipefail

PASS=0; WARN=0; FAIL=0

ok()   { echo "  PASS  $1"; PASS=$((PASS+1)); }
warn() { echo "  WARN  $1"; WARN=$((WARN+1)); }
bad()  { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

echo "=== 1. Секреты и права ==="

if [[ -f .env ]]; then ok ".env на месте"; else bad ".env отсутствует"; fi

for var in SNOWFLAKE_ACCOUNT SNOWFLAKE_USER COPILOT_API_KEY TG_BOT_TOKEN TG_ALLOWED_CHAT_IDS; do
    value=$(grep -E "^${var}=" .env 2>/dev/null | cut -d= -f2- | tr -d '"'"'"' ')
    if [[ -n "$value" ]]; then ok "$var задан"; else bad "$var пуст — сервис не стартует, это fail-closed"; fi
done

KEY_HOST=$(grep -E '^SNOWFLAKE_PRIVATE_KEY_HOST_PATH=' .env 2>/dev/null | cut -d= -f2-)
if [[ -f "$KEY_HOST" ]]; then
    owner=$(stat -c '%u' "$KEY_HOST"); mode=$(stat -c '%a' "$KEY_HOST")
    [[ "$owner" == "10001" ]] && ok "ключ принадлежит uid 10001" \
        || bad "ключ принадлежит uid $owner — контейнер прочитать не сможет"
    [[ "$mode" == "400" || "$mode" == "600" ]] && ok "права на ключ $mode" \
        || warn "права на ключ $mode — ожидались 400"
else
    bad "приватный ключ не найден по пути из .env: $KEY_HOST"
fi

# Ключ не должен попасть в git ни при каких обстоятельствах.
if git -C . check-ignore -q .env 2>/dev/null; then ok ".env под .gitignore"; else warn ".env не игнорируется git"; fi

echo
echo "=== 2. Контейнеры ==="

for svc in api bot; do
    state=$(docker compose ps --format '{{.Service}} {{.State}}' 2>/dev/null | awk -v s="$svc" '$1==s{print $2}')
    [[ "$state" == "running" ]] && ok "$svc запущен" || bad "$svc не запущен (состояние: ${state:-нет})"
done

if docker network inspect llm-shared >/dev/null 2>&1; then ok "сеть llm-shared существует"
else warn "сети llm-shared нет — учёт расхода в hermes-memory работать не будет"; fi

echo
echo "=== 3. API ==="

health=$(curl -s -o /dev/null -w '%{http_code}' http://127.0.0.1:8770/healthz 2>/dev/null)
[[ "$health" == "200" ]] && ok "/healthz отвечает 200" || bad "/healthz вернул ${health:-нет ответа}"

ready=$(curl -s http://127.0.0.1:8770/readyz 2>/dev/null)
if grep -q '"status":"ok"' <<<"$ready"; then
    cards=$(sed -n 's/.*"table_cards":\([0-9]*\).*/\1/p' <<<"$ready")
    [[ "$cards" == "9" ]] && ok "/readyz ok, карточек 9" || warn "/readyz ok, но карточек $cards вместо 9"
else
    reason=$(sed -n 's/.*"reason":"\([^"]*\)".*/\1/p' <<<"$ready")
    bad "/readyz не готов: ${reason:-$ready}"
fi

echo
echo "=== 4. Параметры сессии Snowflake ==="

# Ни один из них не является границей безопасности — граница это права роли.
# Но их отсутствие означает потерю таймаута или привязки вопроса к человеку.
params=$(docker compose logs --tail=200 api 2>/dev/null | grep -c "параметр сессии" || true)
[[ "$params" == "0" ]] && ok "все параметры сессии приняты (таймаут и QUERY_TAG на месте)" \
    || warn "$params предупреждений о параметрах сессии — см. docker compose logs api"

echo
echo "=== 5. Сквозной вопрос агенту ==="

API_KEY=$(grep -E '^COPILOT_API_KEY=' .env 2>/dev/null | cut -d= -f2-)
if [[ -n "$API_KEY" ]]; then
    echo "  (вопрос идёт 20-40 секунд, warehouse поднимается из suspended)"
    answer=$(curl -s -m 180 -X POST http://127.0.0.1:8770/ask \
        -H "X-API-Key: $API_KEY" -H 'Content-Type: application/json' \
        -d '{"question":"What was our Cost of Risk for April 2026?","surface":"check"}' 2>/dev/null)
    if grep -q '14.62' <<<"$answer"; then
        ok "агент вернул канонические 14.62%"
    elif grep -q '14.94' <<<"$answer"; then
        bad "агент вернул 14.94% — смешал CC с GRZD_CLIPPED, правило области продукта не действует"
    else
        bad "ответ не содержит ожидаемого числа: $(head -c 200 <<<"$answer")"
    fi
    grep -q '"tools":\[\]' <<<"$answer" && warn "агент ответил без инструментов — проверьте гранты на SV_COR и поиск" \
        || ok "агент воспользовался инструментами"
else
    warn "COPILOT_API_KEY не прочитан, сквозной вопрос пропущен"
fi

echo
echo "=== 6. Регресс ==="

if [[ -f data/baseline.json ]]; then
    total=$(sed -n 's/.*"total": *\([0-9]*\).*/\1/p' data/baseline.json | head -1)
    acc=$(sed -n 's/.*"accuracy": *\([0-9.]*\).*/\1/p' data/baseline.json | head -1)
    ok "baseline снят: вопросов $total, точность $acc"
else
    warn "baseline не снят — деградацию агента сравнивать не с чем:
        docker compose exec -T api python -m app.eval_agent --save /srv/data/baseline.json"
fi

echo
echo "=== 7. Что отсюда не проверяется ==="
echo "  WARN  network policy на пользователе PLATA_COPILOT_SVC — видно только в Snowflake"
echo "  WARN  доставка в Telegram — проверяется глазами в чате: /help, /alerts, /ask"
WARN=$((WARN+2))

echo
echo "ИТОГО: PASS=$PASS WARN=$WARN FAIL=$FAIL"
[[ "$FAIL" -gt 0 ]] && exit 2
exit 0
