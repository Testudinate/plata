# Реестр объектов песочницы

Что создаём, откуда взято, что известно достоверно, а что домысливаем.
Колонка «Достоверность»: **A** — состав колонок явно описан в приложении;
**B** — таблица названа, колонки названы частично; **C** — упомянута только схема/таблица,
состав придумываем.

Приоритеты: **P0** — без этого не работают демо Part 2–4; **P1** — полнота картины;
**P2** — скелет ради карты схем.

---

## Базы данных

| База | Источник | Схемы | Приоритет |
|------|----------|-------|-----------|
| `ODS` | App A | `pf_engine`, `pf_loans`, `pc_app`, `pc_kernel`, `user_mgmt`, `fx_rates`, `pc_tariffs`, `pf_gl`, `ref` | P0 (частично) |
| `RISK_DM` | App A | `dm`, `tableau`, `dds`, `raw` | P0 |
| `RISK_PROV` | App A | `prov` | P1 |
| `RISK_LEGACY` | App A | `dm` | P2 |
| `RISK_RDS` | App A | `dds` | P2 |
| `POS_PROD` | App A | `dds` | P2 |
| `CREDIT_PROD` | App A | `dbt` | P2 |
| `COLLECTION_PROD` | App A | `dbt` | P2 |
| `PAYMENTS_PROD` | App A | `dbt` | P2 |
| `RISK_GOV` | наше | `meta`, `dq`, `agent` | P0 |

`RISK_GOV` в приложениях отсутствует — это governance-слой, которого у Plata сегодня нет
и создание которого и есть предмет роли.

---

## RISK_DM.DM — витрина

| Объект | Зерно | Достоверность | Приоритет | Что известно / что домысливаем |
|--------|-------|---------------|-----------|--------------------------------|
| `portfolio_cor` | account × report_date | **A** (App B) | P0 | Полный список из 17 колонок с типами дан в приложении. Домысливаем только распределения значений |
| `portfolio_bs` | account × report_date | **B** (App B) | P0 | «структура как у portfolio_cor» + `balance_net`, `balance_net_yield`, `provisions`, `provisions_yield`, `beh_type`, `beh_type_detailed` |
| `stm_cor_cc` | account × statement_num | **B** (App B, C) | P0 | Названы `cor_prnp`, `cor_prnp_gen2`, `avg_balance_prnp_net`, `dpd1_flg`, `dpd1_balance_prnp`, `end_date`, `product_risks`, `util_month`. Остальное домысел |
| `stm_cc` | account × statement_num | **C** | P1 | Только упомянута, колонки не описаны. Берём базовый статементный набор |
| `stm_grzd` | account × statement_num | **C** | P2 | Только в списке weekday-only таблиц |
| `clip_statements` | account × statement_num | **C** | P1 | Только в списке weekday-only таблиц |
| `npv_gen5_details` | account × statement × report_month | **B** (App D, G) | P0 | Названы `cor_total_predict`, `bal_total_predict`, `cor_orig_predict`, `bal_orig_predict`, `cor_total_var`, `bal_total_var` + влитые из `PV_DETAILS`: `active_clients_predict`, `opex_predict`, `funding_predict`, `debt_funding_share` |
| `npv_gen5_agg` | account | **B** (App G) | P0 | `cor_total_predict_lt`, `bal_total_predict_lt` |
| `npv_naive_details` | account × statement | **C** | P2 | Только в списке weekday-only таблиц |
| `accounts` | account | **B** (App B, F) | P0 | `account_id`, `client_id`, `product_risks`, `account_state`, `utilization_date`. **`first_utilization_date` не создаём** — App B говорит, что её нет |
| `utilizations` | account | **B** (App D) | P0 | `account_id`, `utilization_date` |
| `limit_actions` | account × bs_day | **B** (App D) | P1 | `account_id`, `bs_day`, лимит до/после |
| `applications` | application_id | **B** (App F) | P1 | `application_id`, `account_id`, `client_id`, дата, решение |
| `scoring_log` | application × стадия | **B** (App G) | P1 | 4 стадии с префиксами, `pd002`, `pd003`, `pd005`, `pg001`, фрод-скоры |
| `ETL_LOG` | прогон | **C** (App B) | P0 | Назначение описано, колонок нет. Домысливаем: таблица, начало/конец, статус, строк, дата данных |

Отдельно: `NPV_GEN5_PV_DETAILS` **не создаётся** — дропнута (App G). Её отсутствие —
часть демонстрации Part 3.

## RISK_DM.TABLEAU

| Объект | Зерно | Достоверность | Приоритет | Примечание |
|--------|-------|---------------|-----------|-----------|
| `cor_challenger` | account × report_date | **A** (App H) | P0 | 11 колонок названы явно. Фильтр — `account_type`, все COR отрицательные |
| `clip_cor_monthly` | report_month | **B** (App H) | P1 | Состав описан прозой: тотал + инкремент CLIP + база, абсолюты и ставки, 95% CI, доля CLIP, n_accounts |
| `clip_cor_vintage` | clip_vintage × stmt_after_clip × is_clip_freeze | **B** (App H) | P1 | + `vintage_maturity` (`young`/`developing`/`mature`) |

## RISK_DM.DDS / RAW

| Объект | Достоверность | Приоритет |
|--------|---------------|-----------|
| `dds.stm_fact_forecast` | **C** (App D: «предджойненная материализация») | P1 |
| `dds.*`, `raw.*` прочее | **C** | P2 (по одной таблице ради карты) |

## ODS

| Объект | Достоверность | Приоритет | Примечание |
|--------|---------------|-----------|-----------|
| `ref.HOLIDAYS` | **A** (App B) | P0 | 5 колонок с типами + список праздников. Единственная ODS-таблица с полным описанием |
| `pc_kernel.ACCOUNT` | **B** (App A, F) | P0 | `account_id`, `client_id`, `account_state`, `account_type`. **Колонку ключа называем `ID`** — App F предупреждает о разнобое имён |
| `user_mgmt.USER_DATA` | **B** (App A, F) | P0 | `gender`, `birthday`, `state` + `client_id`. PII → на ней демонстрируется маскирование |
| `pf_engine.STATEMENTS` | **B** (App F) | P1 | `statement_id` (INTEGER). Таймстемпы в UTC — воспроизводим расхождение таймзон |
| `pc_tariffs.TARIFFS_ACCOUNTS` | **C** (App A, F) | P2 | джойн по `account_id`, «тарифы/прайсинг» |
| `fx_rates.USDMXN` | **C** (App A) | P2 | история курса |
| `pc_app.*` | **C** (App A) | P2 | транзакции, в т.ч. `SPEI_IN` |
| `pf_loans.*` | **C** (App A) | P2 | транши |
| `pf_gl.GL_ENTRY_SOURCES`, `pf_gl.GL_SOURCE_ENGINE` | **C** (App A) | P2 | вью GL-проводок |

## RISK_PROV.PROV

| Объект | Достоверность | Приоритет | Примечание |
|--------|---------------|-----------|-----------|
| `MXGAAP_PROV_CC` | **B** (App C, G) | P1 | `PROVISIONS`, `EAD`, `BALANCE_MXGAAP`, `GINTEREST_BALANCE_MXGAAP_ADJ`. Формула yield/principal обязана сходиться |
| `ADD_PROV` | **C** (App E) | P2 | доппровизии CNBV для счетов без бюро/финального скоринга |
| `DATA_FOR_DM_REGULATORY_PROVISIONS` | **C** (App E) | P2 | код продукта `TDC` = `CC` — пример проблемы референсных данных |

## Прочие базы (скелеты, P2)

`risk_legacy.dm.pd005_by_stages`, `risk_rds.dds.portfolio_features`,
`credit_prod.dbt.*` (кэшфлоу CC), `collection_prod.dbt.*` (тест-группы коллекшна),
`payments_prod.dbt.emart_transactions`, `pos_prod.dds.*` — по 1–2 таблицы,
чтобы карта схем из Appendix A не врала.

---

## RISK_GOV — наш слой (в приложениях отсутствует)

### meta

| Объект | Назначение |
|--------|-----------|
| `dim_date` | Спайн дат с флагом рабочего дня |
| `ref_product` | Продукты и все алиасы: `CC` = `TDC` = `account_type 'CC'`; `GRZD_CLIPPED` |
| `ref_sign_convention` | таблица+колонка → знак → смысл (из App C), питает DQ-проверку знака |
| `metric_definitions` | Реестр метрик: определение, зерно, формула, аннуализация, владелец, версия |
| `model_registry` | Версии моделей Gen5v0 / v1-old / v1-new, дельты EL LT по винтажам |
| `change_log` | Журнал изменений объектов: ломающее ли, кто затронут, статус уведомления |
| `consumer_registry` | Кто потребляет каждый объект (Tableau, отчётность, LLM-агент) |
| `ownership` | Владелец и стюард на объект/домен |
| `sla` | Пороги свежести в рабочих днях, владелец, действие при нарушении |
| `v_object_catalog` | Каталог поверх `INFORMATION_SCHEMA` + тегов |
| `v_lineage` | Линидж из `ACCOUNT_USAGE.OBJECT_DEPENDENCIES` + ручные рёбра |

### dq

| Объект | Назначение |
|--------|-----------|
| `build_assertions` | Проверки S1–S12 после каждой пересборки |
| собственные DMF | Знак COR, аддитивность Gen3, «нет выходных в stm_*», «COR=0 на statement 1», покрытие прогнозом |
| `v_cor_reconciliation` | Мост: канон → три ведомственных расчёта с вкладом каждого расхождения |
| `v_scorecard` | Светофор по 7 измерениям DMBoK + тренд по неделям |

### agent

| Объект | Назначение |
|--------|-----------|
| `table_cards` | Карточка таблицы: зерно, колонка фильтра продукта, колонка даты, знак, обязательные фильтры, грабли, примеры |
| `join_graph` | Рёбра джойнов из App F как данные: from/to/ключ/кардинальность |
| `pitfalls` | Грабли из App D с полем `detection_sql` |
| `glossary` | App E как таблица, с синонимами |
| `metric_contracts` | Канонические формулы — единственный разрешённый способ считать |
| `eval_questions` | 20–30 золотых вопросов с эталонами — регресс-набор для агента |
| `v_agent_query_audit` | Что агент спрашивал, что вернул, сколько стоило |

---

## Итого

| Приоритет | Объектов | Когда строим |
|-----------|----------|--------------|
| P0 | ~20 | Фазы 2–5, минимальный срез |
| P1 | ~15 | Фазы 5–6 |
| P2 | ~20 (скелеты) | Фаза 6 |
| RISK_GOV | ~25 | Фазы 8–9 |
