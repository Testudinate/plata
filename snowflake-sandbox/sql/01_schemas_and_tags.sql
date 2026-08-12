---------------------------------------------------------------------------
-- Фаза 1. Каркас: схемы по Appendix A + теги governance-слоя.
--
-- Запускается уже из рабочей сессии (роль HERMES_MCP_ROLE), после 00_bootstrap.
-- Оформлено одним анонимным блоком: MCP-инструмент принимает один стейтмент
-- за вызов, батч через ';' работать не будет.
---------------------------------------------------------------------------

EXECUTE IMMEDIATE $$
BEGIN

    -- ---------------------------------------------------------------
    -- Схемы. Имена и назначение — ровно по Appendix A.
    -- ---------------------------------------------------------------

    -- ODS: операционные источники
    CREATE SCHEMA IF NOT EXISTS ODS.PF_ENGINE  COMMENT = 'ODS - PF Engine: statements, account attributes';
    CREATE SCHEMA IF NOT EXISTS ODS.PF_LOANS   COMMENT = 'ODS - PF Loans: tranches';
    CREATE SCHEMA IF NOT EXISTS ODS.PC_APP     COMMENT = 'ODS - PC Application: transactions incl. SPEI_IN';
    CREATE SCHEMA IF NOT EXISTS ODS.PC_KERNEL  COMMENT = 'ODS - PC Kernel: account master (ACCOUNT)';
    CREATE SCHEMA IF NOT EXISTS ODS.USER_MGMT  COMMENT = 'ODS - User Management: demographics (USER_DATA). Contains PII';
    CREATE SCHEMA IF NOT EXISTS ODS.FX_RATES   COMMENT = 'ODS - Banxico/CMEX: FX rate history (USDMXN)';
    CREATE SCHEMA IF NOT EXISTS ODS.PC_TARIFFS COMMENT = 'ODS - PC Tariffs: account tariff assignments';
    CREATE SCHEMA IF NOT EXISTS ODS.PF_GL      COMMENT = 'ODS - General Ledger: journal entry views';
    CREATE SCHEMA IF NOT EXISTS ODS.REF        COMMENT = 'ODS - Reference data: Mexican non-business day calendar';

    -- RISK_DM: аналитический слой
    CREATE SCHEMA IF NOT EXISTS RISK_DM.DM      COMMENT = 'Data Mart: primary analytical layer. Product filter column: PRODUCT_RISKS';
    CREATE SCHEMA IF NOT EXISTS RISK_DM.TABLEAU COMMENT = 'Tableau production tables. Product filter column: ACCOUNT_TYPE (not PRODUCT_RISKS)';
    CREATE SCHEMA IF NOT EXISTS RISK_DM.DDS     COMMENT = 'Detail Data Store: cleaned detailed data, technical layer';
    CREATE SCHEMA IF NOT EXISTS RISK_DM.RAW     COMMENT = 'Raw / staging: raw ingestion, technical layer';

    -- Прочие продуктовые базы
    CREATE SCHEMA IF NOT EXISTS RISK_PROV.PROV       COMMENT = 'Risk Reserves: production MxGAAP provision tables';
    CREATE SCHEMA IF NOT EXISTS RISK_LEGACY.DM       COMMENT = 'Legacy risk DM: PD model outputs. NOT the same as RISK_DM.DM';
    CREATE SCHEMA IF NOT EXISTS RISK_RDS.DDS         COMMENT = 'Risk RDS detail store: feature-engineered portfolio data';
    CREATE SCHEMA IF NOT EXISTS CREDIT_PROD.DBT      COMMENT = 'Credit product: dbt-modeled cashflow tables for CC';
    CREATE SCHEMA IF NOT EXISTS COLLECTION_PROD.DBT  COMMENT = 'Collection: dbt-modeled collection / agency test group tables';
    CREATE SCHEMA IF NOT EXISTS PAYMENTS_PROD.DBT    COMMENT = 'Payment processing: processed transaction data';
    CREATE SCHEMA IF NOT EXISTS POS_PROD.DDS         COMMENT = 'POS detail store: POS-specific detailed data';

    -- RISK_GOV: слой, которого в приложениях нет
    CREATE SCHEMA IF NOT EXISTS RISK_GOV.META  COMMENT = 'Governance metadata: catalog, ownership, metric definitions, change log';
    CREATE SCHEMA IF NOT EXISTS RISK_GOV.DQ    COMMENT = 'Data quality: assertions, custom DMFs, scorecard, reconciliation';
    CREATE SCHEMA IF NOT EXISTS RISK_GOV.AGENT COMMENT = 'LLM context layer: table cards, join graph, pitfalls, metric contracts, evals';

    -- ---------------------------------------------------------------
    -- Теги. Ими в Фазе 8 размечается всё созданное; каталог и DQ-скоркарта
    -- читают именно теги, а не отдельную табличку-дублёр.
    -- ---------------------------------------------------------------

    CREATE TAG IF NOT EXISTS RISK_GOV.META.DATA_DOMAIN
        ALLOWED_VALUES 'credit_risk', 'provisions', 'collections', 'origination', 'customer', 'finance', 'reference', 'governance'
        COMMENT = 'Бизнес-домен объекта';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.DATA_OWNER
        COMMENT = 'Владелец данных: подразделение, отвечающее за смысл и корректность';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.DATA_STEWARD
        COMMENT = 'Стюард: конкретный человек, отвечающий за операционное качество';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.LAYER
        ALLOWED_VALUES 'ods', 'raw', 'dds', 'dm', 'tableau', 'prov', 'gov'
        COMMENT = 'Слой архитектуры данных';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.CRITICALITY
        ALLOWED_VALUES 'tier1', 'tier2', 'tier3'
        COMMENT = 'tier1 - питает отчётность или регуляторику, инцидент эскалируется немедленно';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.CONTAINS_PII
        ALLOWED_VALUES 'yes', 'no'
        COMMENT = 'Наличие персональных данных. Роль LLM_AGENT_RO к yes не допускается';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.SIGN_CONVENTION
        ALLOWED_VALUES 'negative_cost', 'positive_loss', 'not_applicable'
        COMMENT = 'Знаковое соглашение колонки: negative_cost - факт COR, positive_loss - прогноз NPV';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.REFRESH_SLA_HOURS
        COMMENT = 'Порог свежести в часах. Для weekday-only таблиц считается по рабочим дням из ODS.REF.HOLIDAYS';

    CREATE TAG IF NOT EXISTS RISK_GOV.META.DEPRECATED_SINCE
        COMMENT = 'Дата объявления объекта устаревшим. Наличие тега = объект нельзя использовать в новых запросах';

    RETURN 'phase 1 ok';
END;
$$
;
