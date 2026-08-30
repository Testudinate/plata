# Упрощённая презентация для нанимающего менеджера

| Файл | Что это |
|------|---------|
| `plata-risk-governance-presentation-ru.pptx` | Русская версия, 18 слайдов |
| `plata-risk-governance-presentation-en.pptx` | Английская версия, 18 слайдов |
| `content.js` / `build.js` / `icons.js` | Исходники генератора (pptxgenjs) — для воспроизводимости и правок |

В отличие от `../test-assignment-answer-*.pdf` (полный технический ответ),
эта колода — упрощённое изложение того же материала без жаргона DAMA/DMBoK/SQL,
рассчитанное на нетехнического читателя, плюс отдельные технические слайды
(мост метрики, реестр рисков, лестницы зрелости DQM/CM, готовность ИИ-агента,
допущения), напрямую отвечающие на вопросы Parts 1–5 тестового задания.

## Пересборка

```bash
cd answer/presentation
npm install pptxgenjs react-icons react react-dom sharp
node build.js
```
