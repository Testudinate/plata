# Схема TABLEAU — инвентаризация таблиц

*Перевод. Оригинал: [../Test Assignment - Appendices/Appendix H - Tableau Tables.md](../Test%20Assignment%20-%20Appendices/Appendix%20H%20-%20Tableau%20Tables.md)*

## Таблица COR Challenger

### `tableau.cor_challenger`

Гранулярность: `account_id` x `report_date`. Дневной COR с декомпозицией Gen3. Это основная таблица для гранулярного сравнения управленческих резервов Gen2 и Gen3.

**Критично — колонка-фильтр**: используйте `account_type` (НЕ `product_risks`). Значения: CC, GRZD, PL, POS, GRZD_CLIPPED.

Ключевые колонки:

| Колонка | Описание |
|--------|-------------|
| `cor` | Итоговый управленческий COR по Gen3 |
| `cor_total` | Итоговый управленческий COR по Gen2 |
| `cor_1p_fact` | Факт inflow по Gen3 (0→1+ DPD) |
| `cor_1p_predict` | Прогноз inflow по Gen3 |
| `cor_collection_fact` | Факт коллекшена по Gen3 |
| `cor_collection_predict` | Прогноз коллекшена по Gen3 |
| `net_balance_prnp` | Чистый баланс основного долга |
| `balance_prnp` | Валовой баланс основного долга |
| `dlq_days` | Текущий DPD |
| `prev_dlq_days` | DPD за предыдущий день |
| `provisions_dlq_gen3` | Резервы по просрочке, Gen3 |

### Аддитивная декомпозиция

- Gen3: `cor = cor_1p_fact + cor_collection_fact`
- Gen2: `cor_total = cor_dlq_fact + cor_0_bucket`

### Декомпозиция inflow против collection

Компоненты inflow и collection выводятся из `prev_dlq_days`:
```sql
CASE WHEN prev_dlq_days > 0 THEN cor ELSE 0 END AS cor_collection_fact_derived
```

### Декомпозиция Gen3 через `prev_dlq_days`

Помимо базового разделения на inflow/collection, COR по Gen3 можно разложить на более мелкие бакеты DPD с помощью `prev_dlq_days`. Это полезно для bridge-декомпозиции (например, месячных waterfall-графиков COR).

| Компонент | Фильтр | Описание |
|-----------|--------|-------------|
| Рост DPD0 | `cor_0_bucket` | Изменение резерва по работающему портфелю (0 DPD) |
| Inflow 1+ DPD | `cor WHERE prev_dlq_days = 0 AND dlq_days >= 1` | Новые просрочки, входящие в 1+ DPD |
| Коллекшн 1-30 | `cor WHERE prev_dlq_days BETWEEN 1 AND 30` | Ранняя стадия коллекшена |
| Коллекшн 31-90 | `cor WHERE prev_dlq_days BETWEEN 31 AND 90` | Средняя стадия коллекшена |
| Коллекшн 90+ | `cor WHERE prev_dlq_days > 90` | Поздняя стадия (обычно роспуск резерва) |

**Проверка**: компоненты в сумме дают итог по Gen3 (`cor + cor_0_bucket`) с ошибкой округления <0.01 п.п.

Эта декомпозиция обходит известную проблему с данными в `cor_collection_fact` и даёт более гранулярную картину, чем базовая заплатка `CASE WHEN prev_dlq_days > 0`.

### Соглашение о знаках

Все колонки COR в этой таблице **отрицательные** (затраты). При сравнении с прогнозами NPV (которые положительные) поменяйте знак у одной из сторон.

## Витрины инкрементального COR по CLIP

Две материализованные вьюхи для анализа CLIP — можно запрашивать напрямую, без джойнов.

### `tableau.clip_cor_monthly`

Гранулярность: одна строка на `report_month`. Содержит общий CoR портфеля + инкрементальный CoR от CLIP + базовый CoR, абсолютные значения в MXN и аннуализированные ставки, границы 95% доверительного интервала, долю CLIP в общем CoR, n_accounts, итоговые балансы.

### `tableau.clip_cor_vintage`

Гранулярность: одна строка на `clip_vintage` x `stmt_after_clip` x `is_clip_freeze`. Содержит средний инкрементальный CoR, средний инкрементальный баланс, аннуализированный incr_cor_pct, cumulative_cor_incr, границы 95% доверительного интервала, флаг `vintage_maturity` (`'young'` / `'developing'` / `'mature'`).

**Замечание**: для стандартных кривых жизненного цикла всегда фильтруйте `is_clip_freeze = FALSE`. Объяснение когорты freeze — в `risk/pilots.md`.
