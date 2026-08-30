// Shared content model for RU and EN decks — technical/detailed version.

const ru = {
  fontHeader: 'Bookman Old Style',
  fontBody: 'Calibri',

  title: {
    kicker: 'КАНДИДАТ · RISK DATA GOVERNANCE LEAD · PLATA',
    title: 'Я не рассуждал, как бы я исправил ваши данные —\nя исправил их и измерил результат',
    sub: 'Вместо описания подхода я воссоздал часть IT-ландшафта Plata, нашёл реальные проблемы и построил работающее решение. Все цифры ниже — это измерения, а не оценки.',
    stats: [
      { n: '14,62%', l: 'канонический COR\nза апрель 2026' },
      { n: '3,24 п.п.', l: 'разрыв между\nтремя расчётами' },
      { n: '26 / 0', l: 'проверок проходят /\nпровалов' },
      { n: '$8', l: 'стоимость всего\nдоказательства' },
    ],
  },

  problem: {
    kicker: 'ЧАСТЬ 1 · ПРОБЛЕМА',
    title: 'Один показатель — три разных числа',
    intro: 'В материалах задания ключевой показатель риска (COR) считался тремя командами по трём разным формулам — и каждая версия публиковалась как «правильная».',
    cards: [
      { label: 'Финансы', value: '11,38%' },
      { label: 'Мониторинг портфеля', value: '11,92%' },
      { label: 'Официальный расчёт', value: '14,62%' },
    ],
    callout: 'Дело не в ошибке вычисления. Дело в том, что не было ни одной согласованной формулы и ни одного человека, который отвечал бы за неё. И хуже всего: ничего не «падает» и не выдаёт ошибку — отчёты просто тихо показывают разные числа.',
    source: 'Глоссарий сам признаёт: «Three methodologies exist» (Appendix E, строка 13) — ни одна формула не помечена основной.',
  },

  bridge: {
    kicker: 'ЧАСТЬ 1 · ГДЕ РОЖДАЕТСЯ РАЗНИЦА',
    title: 'Мост: как из одного канона получаются два других числа',
    intro: 'Каждый шаг меняет ровно одно методологическое решение и пересчитывается из данных — поэтому остаток равен нулю по построению. Это один расчёт с разными переключателями, а не три случайных числа.',
    headers: ['Шаг (апрель 2026, продукт CC)', 'Вклад', 'Итог'],
    rows: [
      ['Канон — statement, Gen3, stmt ≥ 2, ×12', '—', '14,62%'],
      ['Снят фильтр statement_num ≥ 2', '−0,20', '14,42%'],
      ['Зерно: statement → день', '−2,14', '12,28%'],
      ['Из числителя убран 0-DPD бакет', '−0,53', '11,75%'],
      ['Аннуализация ×12 → ×365', '+0,16', '11,92%'],
      ['= Portfolio Monitoring', '', '11,92%'],
      ['Поколение модели Gen3 → Gen2', '−0,54', '11,38%'],
      ['= Finance', '', '11,38%'],
    ],
    sumRows: [5, 7],
    note: 'Разрыв не имеет постоянного знака: в апреле канон — самое высокое из трёх чисел, в марте — самое низкое. Договорённость «у Finance всегда минус два пункта» невозможна: нужен один канон, а не поправочный коэффициент.',
  },

  riskRegister: {
    kicker: 'ЧАСТЬ 1 · ЧТО РЕАЛЬНО НАЙДЕНО',
    title: 'Реестр рисков — не гипотезы, а цитаты с номером строки',
    headers: ['#', 'Риск', 'Дисциплина DAMA', 'Что написано в материалах'],
    rows: [
      ['R1', 'Метрика без канона', 'Data Quality Mgmt', '«Three methodologies exist» (E:13) — ни одна формула не основная'],
      ['R2', 'Знаковое правило прозой', 'Data Architecture', '«different tables use different signs… silently produces incorrect results» (C:7)'],
      ['R3', 'Разная колонка фильтра', 'Reference Data', "dm.* → product_risks, tableau.* → account_type (A:42) — оба принимают 'CC'"],
      ['R4', 'Правило продублировано трижды', 'Metadata Mgmt', 'statement_num ≥ 2 записан независимо в C:99, D:27, F:53'],
      ['R6', 'Изменение без версии', 'Change Management', '«materially shifted EL LT» (G:71) — схема не менялась, числа изменили смысл'],
      ['R10', 'PII как рядовое обогащение', 'Data Security', 'join к ods.user_mgmt.USER_DATA без классификации (F:29)'],
    ],
    note: 'Всего найдено 20 находок в приложениях A–I, 8 из них критические — полный реестр R1–R11 в развёрнутом ответе.',
  },

  ownership: {
    kicker: 'ЧАСТЬ 1 · ВЛАДЕНИЕ ОПЕРАЦИОННО',
    title: 'Владение — это не строка в Excel, а три разных обязанности',
    headers: ['Роль', 'За что отвечает'],
    rows: [
      ['Data owner', 'Что число означает; подписывает изменение определения'],
      ['Data steward', 'Операционное качество; получает алерт при падении проверки'],
      ['Technical owner', 'Пайплайн и SLA загрузки'],
    ],
    calloutTitle: 'Тест реальности',
    callout: 'Кто подписал определение, кого будят и что он делает, кто должен был узнать заранее и за сколько дней. Пока хоть один ответ добывается обзвоном — владение существует только на бумаге.',
  },

  proof: {
    kicker: 'ЧАСТЬ 2 · ДОКАЗАТЕЛЬСТВО',
    title: 'Я не обсуждал решение — я его построил и проверил',
    bullets: [
      { icon: 'FiDatabase', text: 'Воссоздал часть IT-инфраструктуры Plata в Snowflake: 10 баз, 23 схемы, 59 таблиц, 15 вью, 8,1 млн строк' },
      { icon: 'FiEye', text: 'Нашёл и задокументировал 20 конкретных проблем — 8 критических, у каждой точная ссылка на источник' },
      { icon: 'FiCpu', text: 'Построил рабочую систему: 26 автоматических проверок, канонический метрик-слой, реестр изменений, ИИ-агент RISK_COPILOT' },
    ],
    costBig: '$8',
    costLabel: 'Столько стоила вся проверка в облаке —\n2,67 кредита Snowflake, дешевле часа переговоров',
  },

  fix: {
    kicker: 'ЧАСТЬ 2 · РЕШЕНИЕ',
    title: 'Как это чинится — четыре правила и одно условие на входе',
    cards: [
      { icon: 'FiTarget', title: 'Одно число', text: 'Один официальный способ считать каждый показатель. Остальные версии — архив, а не альтернатива.' },
      { icon: 'FiLock', title: 'Правило внутри системы', text: 'Правило хранится строкой с готовым SQL-условием, а не абзацем в документе.' },
      { icon: 'FiUserCheck', title: 'Именной владелец', text: 'У каждого числа и каждого изменения есть конкретный человек, который отвечает за него.' },
      { icon: 'FiBell', title: 'Изменения без сюрпризов', text: 'Каждое изменение регистрируется и объявляется заранее. Откат — за секунды.' },
    ],
    codeLabel: 'Пример — знаковое правило как код, а не абзац:',
    codeExample: 'COR_PRNP <= 0   -- правило #3, источник: Appendix C, строка 7',
    gate: 'Ворота на входе: у объекта есть карточка, названный владелец и стюард, SLA с действием и пройденный прогон всех проверок — иначе объекта в реестре нет. Нейминг чинится тем же принципом: слой алиасов вместо переименования 20+ схем — старые имена живут, но перестают быть развилкой; миграций ноль.',
  },

  maturity: {
    kicker: 'ЧАСТЬ 3 · ГДЕ СЕЙЧАС PLATA',
    title: 'Зрелость по DAMA: от «в голове» до «система следит сама»',
    headers: ['Дисциплина', 'Уровень сейчас', 'Свидетельство'],
    rows: [
      ['Data Quality Mgmt', 'Basic', 'Свежесть в таблице есть, но нет ни порога, ни владельца, ни следа проверки'],
      ['Change Management', 'Basic', 'Дроп описан как факт; пересчёт — как «имейте в виду»'],
      ['Data Catalog', 'Defined по содержанию /\nBasic по владению', 'Разметка 40 техтаблиц выполнена, владение не оформлено'],
      ['Reference Data', 'Defined', 'Свидетельств мало, видны только продуктовые коды'],
    ],
    legend: 'Basic — практика живёт в головах · Defined — правило записано, есть владелец · Controlled — соблюдение проверяется автоматически · Continuing — измеряется сама система контроля.',
  },

  checks: {
    kicker: 'ЧАСТЬ 3 · АВТОМАТИЧЕСКИЙ КОНТРОЛЬ',
    title: 'Три сигнала, которые ловят дрейф раньше пользователя',
    headers: ['Сигнал', 'Что именно ловит'],
    rows: [
      ['D1 — остаток моста ≠ 0', 'Молча изменившийся расчёт, новую ветку вычисления, сдвиг в данных'],
      ['D2 — вклад шага вне коридора', 'Отклонение от нормальной сезонности (шаг «зерно»: от −7,1 до +8,1 п.п. за 24 месяца)'],
      ['D3 — расчёт разошёлся с формулой', 'Единственная проверка, направленная на людей, а не на данные'],
    ],
    stats: [
      { n: '26 / 0', l: 'проверок проходят / провалов,\n15 категорий' },
      { n: '22 / 1', l: 'DQ-проверок зелёных /\nжёлтых' },
    ],
    calloutTitle: 'Настоящая ошибка, которую я нашёл и исправил',
    callout: 'Индикатор мониторинга показывал «всё зелено», хотя данные реально отставали на 9 рабочих дней — проверялся журнал ETL, а не сами данные. Теперь проверяется факт, а не отчёт о факте.',
  },

  agent: {
    kicker: 'ЧАСТЬ 4 · ГОТОВНОСТЬ К ИИ',
    title: 'ИИ-агент: не демо, а измеренная система',
    archSubhead: 'RISK_COPILOT в Snowflake — три инструмента',
    arch: [
      'Семантическая вью SV_COR — единственный разрешённый способ считать метрику',
      'Cortex Search по приложениям A–I — 86 чанков, документы не покидают аккаунт',
      'SQL только на чтение под ролью LLM_AGENT_RO — без грантов на PII-таблицы',
    ],
    contextLabel: 'Весь контекст-слой — 13 664 символа ≈ 3,4k токенов: помещается в системный промпт целиком',
    evalSubhead: 'Оценено по плану, написанному заранее — 23 вопроса',
    evalHeaders: ['Вердикт', 'n', 'Что это показывает'],
    evalRows: [
      ['PASS', '11', 'Governance держится под агентом: отказ отдать демографию, верный канон с контрактом'],
      ['FAIL', '2', '«22 рабочих дня» вместо 20 — не хватало гранта на календарь праздников'],
      ['PARTIAL', '10', 'Верный вывод и верная ловушка, но не хватило прав на выполнение'],
    ],
    trust: 'Доверие — произведение, а не сумма: права × измеренная правильность × провенанс ответа × прозрачность действий. Обнуление любого множителя даёт ноль, а не «частично доверяем».',
  },

  aiGaps: {
    kicker: 'ЧАСТЬ 4 · ЧЕГО НЕ ХВАТАЕТ АГЕНТУ',
    title: 'Три вещи, которых не хватает агенту — и ворота до доверия',
    archSubhead: 'Агенту не хватает',
    arch: [
      'Структуры вместо прозы — строка, найденная запросом по имени объекта, а не абзац',
      "Разрешения терминов — глоссарий знает, что TDC значит кредитная карта, но не что в запросе это product_risks = 'CC'",
      'Правил внутри данных, а не рядом — фильтр в документе можно проигнорировать, зашитый в метрику — нельзя',
    ],
    evalSubhead: 'Пробелы доверия — что закрыто, что открыто',
    evalHeaders: ['Пробел', 'Статус'],
    evalRows: [
      ['G1 — порог годности', 'Закрыт — baseline снят, --compare валит прогон при деградации'],
      ['G2 — ресурсные ограничения', 'Закрыты на границе сервиса — сессии по 90 сек на отдельном warehouse'],
      ['G3 — провенанс ответа', 'Частично — контракт называется, снимка модели и даты данных нет'],
      ['G4 — доверие бинарно', 'Открыт — нужны три класса доступа: аналитика / отчётность / регуляторика'],
    ],
    note: 'Чтобы Data Catalog поднялся до Controlled для ИИ-потребления: обязательная карточка на входе (M4), автопроверка соответствия схемы, agent readiness — часть definition of done для нового объекта.',
  },

  change: {
    kicker: 'ЧАСТЬ 4 · УПРАВЛЕНИЕ ИЗМЕНЕНИЯМИ',
    title: 'Gen5v1: данные изменились, схема — нет',
    intro: 'Ничего не падает, запросы не выдают ошибок — дашборды просто тихо показывают другие числа. Сдвиг EL LT на 35% для винтажей 2025 H1 нашли только через квартал, на разборе отклонений. Это опаснее сноса таблицы: снос заметен через минуту.',
    headers: ['Потребитель', 'Уведомление', 'Что именно ломает'],
    rows: [
      ['Модель решений (CLIP)', '30 дней', 'Сдвиг EL LT — модель на нём калибрована'],
      ['Месячная отчётность', '20 дней', 'Изменение значений в закрытых периодах'],
      ['Дашборд статементного COR', '10 дней', 'Любое изменение значений прогноза или зерна'],
      ['ИИ-агент', '0 дней', 'Изменение значений требует обновления контекста, а не уведомления'],
    ],
    rollback: 'Путь отката: переключение вью, а не перезаливка данных — оба снимка живы, откат стоит секунд.',
  },

  changeLadder: {
    kicker: 'ЧАСТЬ 4 · ЛЕСТНИЦА CHANGE MANAGEMENT',
    title: 'Gen5v1 в терминах лестницы зрелости Change Management',
    headers: ['Ступень', 'Что реализовано'],
    rows: [
      ['Basic', 'Изменение узнают постфактум — так выглядел бы этот кейс без вмешательства'],
      ['Defined', 'CHANGE_LOG: 4 записи, 3 из них помечены как «ломающие»'],
      ['Controlled', 'Вью влияния, версионирование снимков, окно параллельной работы, «надгробие» вместо ошибки object does not exist'],
      ['Continuing', 'Снимки DDL и сверка хеша: изменившийся хеш без записи в журнале — это вердикт, а не мнение'],
    ],
    note: 'Gen5v1 закрыт на уровне Controlled: оба снимка (2026-03 и 2026-06) живы, откат — переключением вью. До Continuing не хватает автоматической сверки хеша на каждый пересчёт.',
  },

  plan90: {
    kicker: 'ЧАСТЬ 5 · ПОЧЕМУ ИМЕННО ЭТИ ДВА',
    title: 'DQM и Change Management — первыми, и вот почему',
    reasoning: 'Не только потому что задание называет их самой острой болью, но и по порядку зависимостей: без DQ нельзя доказать, что изменение что-то сломало, а без управления изменениями любое улучшение качества откатывается следующим релизом. Параллельно — канонический метрик-слой: нельзя мониторить качество метрики, определение которой не зафиксировано.',
    measureSubhead: 'Первые 30 дней измеряю:',
    measures: [
      'Сколько версий одной метрики в обращении',
      'Доля инцидентов, найденных мониторингом раньше пользователя',
      'Доля зарегистрированных изменений схемы',
      'Время ответа на типовой вопрос аналитика',
      'Доля правильных ответов агента на золотом наборе',
    ],
    notPrioritySubhead: 'Сознательно не приоритет на 90 дней:',
    notPriority: [
      'Reference Data Management — справочник с алиасами закрывает 90% боли за день',
      'MDM по клиентам',
      'Смена платформы или закупка каталога — инструмент раньше процесса консервирует его отсутствие',
      'Покрытие владением tier3 — разметка техтаблиц создаёт видимость governance, а не саму governance',
    ],
  },

  plan: {
    kicker: 'ЧАСТЬ 5 · ПЕРВЫЕ 90 ДНЕЙ',
    title: 'Первые 90 дней — по шагам, с доказательством на каждом',
    steps: [
      { day: 'День 30', text: 'Пять замеров снято; канон метрики зафиксирован и подписан; мост между тремя расчётами считается' },
      { day: 'День 60', text: 'Проверки на всех tier1 с порогом, стюардом и предписанным действием; журнал изменений заведён' },
      { day: 'День 90', text: 'Реестр потребителей со сроками уведомления; сверка снимков схемы работает автоматически' },
    ],
  },

  team: {
    kicker: 'ЧАСТЬ 5 · КОМАНДА',
    title: 'Как я организую работу команды',
    cards: [
      { title: 'Стюард 1', subtitle: 'Витрины и качество данных', text: 'Проверки качества, дежурство по инцидентам, свежесть данных' },
      { title: 'Стюард 2', subtitle: 'Смысл и правила', text: 'Определения показателей, глоссарий, журнал изменений' },
    ],
    principles: [
      'Сначала снимаю с людей лишнюю работу, потом добавляю новую',
      'Учу на первом примере вместе — дальше делают сами',
      'Ревью объясняет причину отказа, а не просто говорит «нет»',
    ],
  },

  assumptions: {
    kicker: 'ДОПУЩЕНИЯ',
    title: 'Что я предполагаю сверх материалов приложений',
    items: [
      '«Tier1» — таблицы, питающие модели решений (например CLIP) и внешнюю отчётность; остальное отнесено к tier2/tier3',
      'Ретроспективный пересчёт закрытых периодов требует отдельного решения Head of IRM совместно с Finance; по умолчанию — «только вперёд»',
      'У ИИ-агента нет прав на ODS/PII-таблицы, пока не пройдена классификация данных силами Security/Legal',
      'DWH Engineering не подчиняется governance-роли операционно — все проверки строятся на стороне риска, без изменений в upstream-пайплайнах',
      'Песочница в Snowflake — приближение продуктивной среды (те же зёрна и знаковые соглашения), а не точная копия объёмов данных',
    ],
  },

  closing: {
    kicker: 'ИТОГ',
    title: 'Почему это важно для Plata',
    body: 'Более надёжные решения. Меньше сюрпризов в отчётности. Безопасное внедрение ИИ. Доверие к данным, которое можно измерить — а не просто продекларировать.',
    footer: 'Полное техническое доказательство (20 стр., запросы и ссылки на источники) — по запросу.',
  },
};

const en = {
  fontHeader: 'Bookman Old Style',
  fontBody: 'Calibri',

  title: {
    kicker: 'CANDIDATE · RISK DATA GOVERNANCE LEAD · PLATA',
    title: "I didn't argue how I'd fix your data —\nI fixed it and measured the result",
    sub: "Instead of describing an approach, I rebuilt part of Plata's data landscape, found real problems in it, and built a working fix. Every number below is a measurement, not an estimate.",
    stats: [
      { n: '14.62%', l: 'canonical COR\nfor April 2026' },
      { n: '3.24 pts', l: 'gap between\nthree calculations' },
      { n: '26 / 0', l: 'checks passing /\nfailing' },
      { n: '$8', l: 'total cost of\nthe entire proof' },
    ],
  },

  problem: {
    kicker: 'PART 1 · THE PROBLEM',
    title: 'One metric — three different numbers',
    intro: 'In the case materials, the key risk metric (COR) was calculated by three teams using three different formulas — and each version was published as “the truth.”',
    cards: [
      { label: 'Finance', value: '11.38%' },
      { label: 'Portfolio Monitoring', value: '11.92%' },
      { label: 'Canonical calculation', value: '14.62%' },
    ],
    callout: "This isn't a calculation error. It's that no single formula was agreed on, and no one owned it. Worse: nothing “breaks” or throws an error — reports just quietly show different numbers.",
    source: 'The glossary admits it outright: “Three methodologies exist” (Appendix E, line 13) — no formula is flagged as primary.',
  },

  bridge: {
    kicker: 'PART 1 · WHERE THE GAP COMES FROM',
    title: 'The bridge: how one canon produces two other numbers',
    intro: 'Each step changes exactly one methodology decision and is recomputed from data — so the residual is zero by construction. This is one calculation with different switches, not three unrelated numbers.',
    headers: ['Step (April 2026, product CC)', 'Contribution', 'Result'],
    rows: [
      ['Canon — statement, Gen3, stmt ≥ 2, ×12', '—', '14.62%'],
      ['Remove filter statement_num ≥ 2', '−0.20', '14.42%'],
      ['Grain: statement → day', '−2.14', '12.28%'],
      ['Remove 0-DPD bucket from numerator', '−0.53', '11.75%'],
      ['Annualization ×12 → ×365', '+0.16', '11.92%'],
      ['= Portfolio Monitoring', '', '11.92%'],
      ['Model generation Gen3 → Gen2', '−0.54', '11.38%'],
      ['= Finance', '', '11.38%'],
    ],
    sumRows: [5, 7],
    note: 'The gap has no fixed sign: in April the canon is the highest of the three numbers, in March it was the lowest. An agreement like “Finance is always two points lower” is impossible — you need one canon, not a correction factor.',
  },

  riskRegister: {
    kicker: 'PART 1 · WHAT WAS ACTUALLY FOUND',
    title: 'Risk register — not hypotheses, quotes with a line number',
    headers: ['#', 'Risk', 'DAMA discipline', 'What the materials actually say'],
    rows: [
      ['R1', 'Metric with no canon', 'Data Quality Mgmt', '“Three methodologies exist” (E:13) — no formula is flagged as primary'],
      ['R2', 'Sign convention in prose', 'Data Architecture', '“different tables use different signs… silently produces incorrect results” (C:7)'],
      ['R3', 'Different filter column', 'Reference Data', "dm.* → product_risks, tableau.* → account_type (A:42) — both accept 'CC'"],
      ['R4', 'Key rule duplicated 3x', 'Metadata Mgmt', 'statement_num ≥ 2 recorded independently in C:99, D:27, F:53'],
      ['R6', 'Change with no version', 'Change Management', '“materially shifted EL LT” (G:71) — schema unchanged, numbers changed meaning'],
      ['R10', 'PII as routine enrichment', 'Data Security', 'join to ods.user_mgmt.USER_DATA with no classification (F:29)'],
    ],
    note: '20 findings total across Appendices A–I, 8 of them critical — the full R1–R11 register is in the extended answer.',
  },

  ownership: {
    kicker: "PART 1 · OWNERSHIP, OPERATIONALLY",
    title: "Ownership isn't a spreadsheet column — it's three separate duties",
    headers: ['Role', 'Accountable for'],
    rows: [
      ['Data owner', 'What the number means; signs off on any change to its definition'],
      ['Data steward', 'Operational quality; gets the alert when a check fails'],
      ['Technical owner', 'The pipeline and the load SLA'],
    ],
    calloutTitle: 'The reality test',
    callout: 'Who signed the definition, who gets woken up and what they do, who should have known in advance and how many days ahead. As long as any one answer requires a phone call, ownership exists on paper only.',
  },

  proof: {
    kicker: 'PART 2 · THE PROOF',
    title: "I didn't discuss a solution — I built and tested one",
    bullets: [
      { icon: 'FiDatabase', text: "Rebuilt part of Plata's data infrastructure in Snowflake: 10 databases, 23 schemas, 59 tables, 15 views, 8.1M rows" },
      { icon: 'FiEye', text: 'Found and documented 20 concrete issues — 8 critical, each with an exact source reference' },
      { icon: 'FiCpu', text: 'Built a working system: 26 automated checks, a canonical metric layer, a change registry, and the RISK_COPILOT AI agent' },
    ],
    costBig: '$8',
    costLabel: 'Total cost of the entire cloud proof —\n2.67 Snowflake credits, cheaper than one hour of talk',
  },

  fix: {
    kicker: 'PART 2 · THE FIX',
    title: 'The fix — four rules and one gate at the door',
    cards: [
      { icon: 'FiTarget', title: 'One number', text: 'One official way to calculate each metric. Every other version is an archive, not an alternative.' },
      { icon: 'FiLock', title: 'Rules live in the system', text: 'A rule is stored as a row with a ready SQL condition, not a paragraph in a document.' },
      { icon: 'FiUserCheck', title: 'A named owner', text: 'Every number and every change has one specific person accountable for it.' },
      { icon: 'FiBell', title: 'No silent changes', text: 'Every change is logged and announced in advance. Rollback takes seconds.' },
    ],
    codeLabel: 'Example — a sign rule as code, not a paragraph:',
    codeExample: 'COR_PRNP <= 0   -- rule #3, source: Appendix C, line 7',
    gate: "The gate at the door: an object needs a card, a named owner and steward, an SLA with an action, and a passing run of every check — otherwise it never enters the registry. Naming is fixed the same way: an alias layer instead of renaming 20+ schemas — old names stay alive but stop being a fork point; zero migrations.",
  },

  maturity: {
    kicker: 'PART 3 · WHERE PLATA STANDS TODAY',
    title: "DAMA maturity: from “in people's heads” to “the system watches itself”",
    headers: ['Discipline', 'Current level', 'Evidence'],
    rows: [
      ['Data Quality Mgmt', 'Basic', 'Freshness is tracked, but there is no threshold, no owner, no audit trail'],
      ['Change Management', 'Basic', 'A drop is documented as a fact; a recalculation as a “heads up”'],
      ['Data Catalog', 'Defined by content /\nBasic by ownership', '40 technical tables tagged; ownership never formalized'],
      ['Reference Data', 'Defined', 'Little evidence, and it is indirect — only product codes are visible'],
    ],
    legend: 'Basic — the practice lives in people\'s heads · Defined — the rule is written down and owned · Controlled — compliance is checked automatically · Continuing — the control system itself is measured.',
  },

  checks: {
    kicker: 'PART 3 · AUTOMATED CONTROL',
    title: 'Three signals that catch drift before the user does',
    headers: ['Signal', 'What it actually catches'],
    rows: [
      ['D1 — bridge residual ≠ 0', 'A silently changed calculation, a new computation branch, a shift in the data'],
      ['D2 — step contribution outside its corridor', 'Deviation from normal seasonality (the “grain” step ranges from −7.1 to +8.1 pts over 24 months)'],
      ['D3 — team calculation diverges from the registered formula', 'The one check aimed at people, not at data'],
    ],
    stats: [
      { n: '26 / 0', l: 'checks passing / failing,\n15 categories' },
      { n: '22 / 1', l: 'DQ checks green /\nyellow' },
    ],
    calloutTitle: 'A real bug I found and fixed',
    callout: 'A monitoring dashboard showed “all green” while the underlying data was actually 9 business days late — it was checking the ETL log, not the data itself. Now it checks the fact, not the report about the fact.',
  },

  agent: {
    kicker: 'PART 4 · AI READINESS',
    title: 'The AI agent: not a demo — a measured system',
    archSubhead: 'RISK_COPILOT in Snowflake — three tools',
    arch: [
      'Semantic view SV_COR — the one permitted way to calculate the metric',
      'Cortex Search over Appendices A–I — 86 chunks, documents never leave the account',
      'Read-only SQL under role LLM_AGENT_RO — no grants on PII tables',
    ],
    contextLabel: "The entire context layer — 13,664 characters, ≈3.4k tokens: fits whole in the system prompt",
    evalSubhead: 'Scored against a plan written in advance — 23 questions',
    evalHeaders: ['Verdict', 'n', 'What it shows'],
    evalRows: [
      ['PASS', '11', 'Governance holds under the agent: refuses to hand over demographics, returns the canon with its contract'],
      ['FAIL', '2', '"22 business days" instead of 20 — missing a grant on the holiday calendar'],
      ['PARTIAL', '10', 'Correct answer, correct trap spotted, but lacked permission to execute'],
    ],
    trust: 'Trust is a product, not a sum: access rights × measured correctness × answer provenance × visibility into what it did. Zeroing out any one factor gives zero — not “partial trust.”',
  },

  aiGaps: {
    kicker: 'PART 4 · WHAT THE AGENT LACKS',
    title: 'Three things the agent lacks — and the gate before trust',
    archSubhead: 'The agent lacks',
    arch: [
      'Structure instead of prose — a row found by querying an object name, not a paragraph',
      "Term resolution — the glossary knows TDC means credit card, but not that in a query it's product_risks = 'CC'",
      'Rules inside the data, not next to it — a filter in a document can be skipped; one built into the metric cannot',
    ],
    evalSubhead: 'Trust gaps — closed vs. open',
    evalHeaders: ['Gap', 'Status'],
    evalRows: [
      ['G1 — fitness threshold', 'Closed — baseline captured; --compare fails the run on regression'],
      ['G2 — resource limits', 'Closed at the service boundary — 90-second sessions on a dedicated warehouse'],
      ['G3 — answer provenance', 'Partial — the contract is named; no model snapshot or data-as-of date'],
      ['G4 — trust is binary', 'Open — needs three access classes: analytics / reporting / regulatory'],
    ],
    note: 'For the Data Catalog to reach Controlled for AI consumption: a mandatory card at entry (M4), automatic schema-conformance checks, and agent readiness as part of the definition of done for every new object.',
  },

  change: {
    kicker: 'PART 4 · CHANGE MANAGEMENT',
    title: 'Gen5v1: the data changed, the schema did not',
    intro: "Nothing breaks, no query throws an error — dashboards just quietly show different numbers. A 35% shift in EL LT for the 2025 H1 vintages was only caught a quarter later, during variance review. That's more dangerous than dropping a table: a drop is noticed in a minute.",
    headers: ['Consumer', 'Notice window', 'What it actually breaks'],
    rows: [
      ['Decision model (CLIP)', '30 days', 'EL LT shift — the model is calibrated on it'],
      ['Monthly reporting', '20 days', 'Value changes inside already-closed periods'],
      ['Statement COR dashboard', '10 days', 'Any change to forecast values or grain'],
      ['AI agent', '0 days', 'A value change needs a context refresh, not a notice'],
    ],
    rollback: 'The rollback path: switch the view, not reload the data — both snapshots stay live, rollback takes seconds.',
  },

  changeLadder: {
    kicker: 'PART 4 · THE CHANGE MANAGEMENT LADDER',
    title: 'Gen5v1 in terms of the Change Management maturity ladder',
    headers: ['Rung', 'What is actually in place'],
    rows: [
      ['Basic', 'A change is discovered after the fact — how this case would have looked without intervention'],
      ['Defined', 'CHANGE_LOG: 4 entries, 3 flagged as breaking'],
      ['Controlled', 'An impact view, snapshot versioning, a parallel-run window, a "tombstone" instead of an object-does-not-exist error'],
      ['Continuing', 'DDL snapshots plus hash reconciliation: a changed hash with no log entry is a verdict, not an opinion'],
    ],
    note: 'Gen5v1 sits at Controlled: both snapshots (2026-03 and 2026-06) stay live, rollback is a view switch. Reaching Continuing still needs automatic hash reconciliation on every recalculation.',
  },

  plan90: {
    kicker: 'PART 5 · WHY THESE TWO, FIRST',
    title: 'DQM and Change Management first — and here is why',
    reasoning: "Not only because the assignment names them as the sharpest pain, but by dependency order: without DQ you can't prove a change broke anything, and without change management any quality improvement gets rolled back by the next release. In parallel: the canonical metric layer — you can't monitor the quality of a metric whose definition was never fixed.",
    measureSubhead: 'What I measure in the first 30 days:',
    measures: [
      'How many versions of one metric are in circulation',
      'Share of incidents caught by monitoring before the user',
      'Share of schema changes that are actually logged',
      "Response time on an analyst's typical question",
      "Share of correct agent answers on the golden set",
    ],
    notPrioritySubhead: 'Deliberately not a priority for 90 days:',
    notPriority: [
      'Reference Data Management — an alias directory closes 90% of the pain in a day',
      'Customer MDM',
      'A platform switch or catalog purchase — a tool bought ahead of the process just preserves its absence',
      'Tier-3 ownership coverage — tagging technical tables creates the appearance of governance, not governance itself',
    ],
  },

  plan: {
    kicker: 'PART 5 · THE FIRST 90 DAYS',
    title: 'The first 90 days, step by step — with proof at each gate',
    steps: [
      { day: 'Day 30', text: 'Five measurements taken; the metric canon is signed off; the bridge between the three calculations reconciles' },
      { day: 'Day 60', text: 'Checks live on every tier-1 object with a threshold, a steward, and a defined action; the change log is live' },
      { day: 'Day 90', text: 'A consumer registry with notice windows; schema-snapshot reconciliation runs automatically' },
    ],
  },

  team: {
    kicker: 'PART 5 · THE TEAM',
    title: "How I'd run the team",
    cards: [
      { title: 'Steward 1', subtitle: 'Dashboards & data quality', text: 'Quality checks, incident on-call, data freshness' },
      { title: 'Steward 2', subtitle: 'Meaning & rules', text: 'Metric definitions, glossary, change log' },
    ],
    principles: [
      'Remove existing busywork before adding new work',
      'Teach on the first example together — then they own it',
      'Every review explains the reason, not just “no”',
    ],
  },

  assumptions: {
    kicker: 'ASSUMPTIONS',
    title: 'What I assume beyond the appendix materials',
    items: [
      '"Tier-1" means tables feeding decision models (e.g. CLIP) and external reporting; everything else is tier-2/tier-3',
      'Retroactive recalculation of closed periods needs a separate decision by the Head of IRM with Finance; the default is "forward only"',
      'The AI agent holds no grants on ODS/PII tables until Security/Legal complete data classification',
      "DWH Engineering doesn't report into the governance role operationally — every check is built on the risk side, with no changes required in upstream pipelines",
      'The Snowflake sandbox approximates the production environment (same grains and sign conventions), not an exact copy of data volumes',
    ],
  },

  closing: {
    kicker: 'WHY IT MATTERS',
    title: 'Why this matters for Plata',
    body: 'Better decisions. Fewer surprises in reporting. Safer AI adoption. Trust in data that can be measured — not just declared.',
    footer: 'Full technical proof (20 pages, with queries and source references) available on request.',
  },
};

module.exports = { ru, en };
