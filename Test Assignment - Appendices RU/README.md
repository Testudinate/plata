# Приложения к тестовому заданию — русская версия

Перевод всех приложений из папки [Test Assignment - Appendices](../Test%20Assignment%20-%20Appendices).
Имена файлов совпадают с оригинальными, чтобы ссылки между документами были сопоставимы.

| Приложение | Файл | О чём |
|-----------|------|-------|
| A | [Appendix A - Schema Map.md](Appendix%20A%20-%20Schema%20Map.md) | Карта баз данных и схем |
| B | [Appendix B - DM Key Tables.md](Appendix%20B%20-%20DM%20Key%20Tables.md) | Ключевые таблицы схемы DM, свежесть данных, календарь праздников |
| C | [Appendix C - Business Concepts.md](Appendix%20C%20-%20Business%20Concepts.md) | Управленческий COR, соглашения о знаках, винтажи |
| D | [Appendix D - Query Patterns.md](Appendix%20D%20-%20Query%20Patterns.md) | Паттерны запросов и подводные камни |
| E | [Appendix E - Glossary.md](Appendix%20E%20-%20Glossary.md) | Глоссарий |
| F | [Appendix F - ID Formats.md](Appendix%20F%20-%20ID%20Formats.md) | Форматы идентификаторов и ключи джойнов |
| G | [Appendix G - Provision Models.md](Appendix%20G%20-%20Provision%20Models.md) | Модели резервов (Gen2/Gen3/Gen5), скоринг |
| H | [Appendix H - Tableau Tables.md](Appendix%20H%20-%20Tableau%20Tables.md) | Таблицы схемы TABLEAU |
| I | [Appendix I - Maturity Assessment.md](Appendix%20I%20-%20Maturity%20Assessment.md) | Оценка текущего уровня зрелости |

Само задание по-русски — [../Test Assignment - Risk Data Governance Lead.ru.md](../Test%20Assignment%20-%20Risk%20Data%20Governance%20Lead.ru.md).

## Что не переводилось

Оставлены на английском, чтобы запросы можно было копировать как есть и сверять
с оригиналом:

- сам SQL-код в блоках, имена баз, схем, таблиц и колонок (`dm.stm_cor_cc`,
  `cor_prnp`, ...). Переведены только комментарии внутри SQL — код от этого
  не меняется;
- значения-константы (`'CC'`, `GRZD_CLIPPED`, `'WEEKEND'`, `'young'`), названия поколений
  моделей (Gen2/Gen3/Gen5v1) и слоёв (Data Mart, DDS, ODS, Tableau);
- дисциплины и уровни зрелости DMBoK (Data Quality Management, Basic → Defined →
  Controlled → Continuing improvement) — на них ссылается формулировка задания;
- отраслевые сокращения из глоссария (COR, DPD, EAD, CLIP, WO, ...): в приложении E
  дана расшифровка на русском, но сам термин сохранён — им оперируют таблицы и запросы;
- испанские названия мексиканских праздников и продуктов (Semana Santa, Tarjeta de Credito).
