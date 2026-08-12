# Глоссарий

*Перевод. Оригинал: [../Test Assignment - Appendices/Appendix E - Glossary.md](../Test%20Assignment%20-%20Appendices/Appendix%20E%20-%20Glossary.md)*

## Термины

| Термин | Расшифровка | Контекст |
|------|---------|---------|
| BS | Balance Sheet (баланс) | `portfolio_bs` — дневная таблица балансов/резервов |
| BdC | Buro de Credito | Мексиканское кредитное бюро (Circulo de Credito) |
| CAR | Capital Adequacy Ratio (достаточность капитала) | Регуляторная метрика капитала, KPI уровня CRO |
| CC | Credit Card (кредитная карта) | Продуктовая линия (основная) |
| CLIP | Credit Limit Increase Program | Автоматическое управление лимитами |
| COR | Cost of Risk (стоимость риска) | Расход на резервы как % от портфеля. Существует три методологии. |
| CSP | Collection Strategy Platform | Технологическая платформа стратегий коллекшена |
| CUBE | Внутренняя книга управленческой отчётности | Мастер-файл Excel для управленческой отчётности |
| Califica | BDC Trans Union Califica | Обязательный по требованию CNBV продукт бюро для переменных EPRC в резервах MxGAAP. |
| DDS | Detail Data Store | Слой очищенных детальных данных |
| DM | Data Mart (витрина данных) | Основная аналитическая схема |
| DPD | Days Past Due (дней просрочки) | Мера просрочки (1 DPD, 30 DPD, 60 DPD, 90+ DPD) |
| EAD | Exposure at Default | Баланс на момент дефолта |
| ECL | Expected Credit Loss | Методология резервирования по IFRS 9 |
| EL LT | Expected Loss Lifetime | Аннуализированный прогноз COR за срок жизни из NPV-модели. Формула: `cor_predict_lt / bal_predict_lt * 12` |
| EPRC | Expected Probability of Recurrent Credit | Ключевая входная переменная модели резервов CNBV, источник — Califica (сейчас) или внутренняя модель (легаси) |
| FvsP | Fact vs Plan (факт против плана) | Колонки сравнения в CUBE (в абсолюте и в %) |
| GRZD | Garantizada | Обеспеченный/гарантированный кредитный продукт |
| IFRS | International Financial Reporting Standards | Международные стандарты отчётности |
| IRM | Integrated Risk Management | Риск-команда (Group IRM) |
| LGD | Loss Given Default | Дополнение к уровню возврата (recovery rate) |
| MxGAAP | Mexican GAAP | Локальные стандарты бухучёта |
| NPV | Net Present Value | Модель прибыльности на уровне счёта (Gen5) |
| ODS | Operational Data Store | Операционные данные исходных систем |
| PD | Probability of Default | Выход скоринговой модели |
| PL | Personal Loan (кэш-кредит) | Продуктовая линия |
| POS | Point of Sale | Продуктовая линия точек продаж |
| SOX | Sarbanes-Oxley | Стандарт комплаенса США |
| SPEI | Sistema de Pagos Electronicos Interbancarios | Мексиканская система межбанковских переводов |
| STM | Statement (выписка) | `stm_cc` — метрики CC на уровне выписки |
| TDC | Tarjeta de Credito | Код продукта CC в таблице `DATA_FOR_DM_REGULATORY_PROVISIONS`. Эквивалент `'CC'` в других схемах. |
| TTM | Time to Market | Метрика скорости поставки Risk IT по бакетам сложности |
| TUC | Total Upfront Cost | Стоимость привлечения на одну утилизацию (4 бакета) |
| WO | Write-Off (списание) | Снятие баланса счёта с учёта после длительной просрочки. Происходит ежеквартально (дек/мар/июн/сен). |
| add_prov | Additional Provisions (дополнительные резервы) | Обязательные по CNBV резервы по счетам с неполной кредитной оценкой (нет отчёта бюро или нет финального скоринга). Таблица: `risk_prov.prov.ADD_PROV`. |
