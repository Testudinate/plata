# Карта баз данных и схем

*Перевод. Оригинал: [../Test Assignment - Appendices/Appendix A - Schema Map.md](../Test%20Assignment%20-%20Appendices/Appendix%20A%20-%20Schema%20Map.md)*

## Инвентаризация схем

| База.Схема | Слой | Описание |
|--------|-------|-------------|
| `risk_dm.dm` | **Data Mart** | Агрегированные таблицы управленческого уровня — основной аналитический слой |
| `risk_dm.tableau` | **Tableau** | Продовые таблицы, питающие дашборды Tableau |
| `risk_legacy.dm` | Risk (legacy DM) | Выходы PD-моделей (`pd005_by_stages`), заявки на кэш-кредиты. **Внимание**: это не то же самое, что `risk_dm.dm` |
| `risk_prov.prov` | Резервы риска (Provisions) | Продовые таблицы резервов MxGAAP |
| `risk_dm.dds` | Detail Data Store | Очищенные детальные данные — технический слой |
| `risk_dm.raw` | Raw / Staging | Таблицы сырой загрузки — технический слой |
| `risk_rds.dds` | Risk RDS Detail Store | Портфельные данные с рассчитанными признаками (`portfolio_features`) |
| `pos_prod.dds` | POS Detail Store | Детальные данные по POS — технический слой |
| `credit_prod.dbt` | Credit Product (dbt) | Таблицы денежных потоков по CC, смоделированные в dbt |
| `collection_prod.dbt` | Collection (dbt) | Таблицы коллекшена / тестовых групп агентств, смоделированные в dbt |
| `payments_prod.dbt` | Payment Processing (dbt) | Обработанные транзакционные данные (`emart_transactions`) |
| `ods.pf_engine` | ODS – PF Engine | Операционные данные: выписки (statements), атрибуты счетов |
| `ods.pf_loans` | ODS – PF Loans | Операционные данные: транши |
| `ods.pc_app` | ODS – PC Application | Операционные данные: транзакции (включая SPEI_IN) |
| `ods.pc_kernel` | ODS – PC Kernel | Мастер-источник счетов (`ACCOUNT`: account_id, client_id, account_state, account_type) |
| `ods.user_mgmt` | ODS – User Management | Демография пользователей (`USER_DATA`: gender, birthday, state) |
| `ods.fx_rates` | ODS – Banxico/CMEX | Валютные курсы: история курса `USDMXN` |
| `ods.pc_tariffs` | ODS – PC Tariffs | Привязка тарифов/ценообразования к счетам (`TARIFFS_ACCOUNTS`) |
| `ods.pf_gl` | ODS – General Ledger | Вьюхи проводок главной книги (`GL_ENTRY_SOURCES`, `GL_SOURCE_ENGINE`). См. `finance/gl_tables.md` |

## Как этим пользоваться

**Для аналитических запросов**: начинайте с `risk_dm.dm` (Data Mart). Это основной слой для управленческой отчётности, с заранее сджойненными и агрегированными таблицами.

**Для данных дашбордов**: используйте `risk_dm.tableau` — эти таблицы специально структурированы под потребление в Tableau.

**Для сырых/исходных данных**: используйте схемы DDS/RAW или таблицы ODS. Подробности — в `tables_technical.md`.

**Для резервов**: MxGAAP в `risk_prov.prov`.

## Важные детали схем

### Разница в фильтре по продукту (критично)

| Схема | Колонка-фильтр | Значение для CC |
|--------|--------------|----------|
| таблицы `dm.*` | `product_risks` | `'CC'` |
| таблицы `tableau.*` | `account_type` | `'CC'` |

Использование не той колонки-фильтра молча возвращает пустой результат или неверные данные.
