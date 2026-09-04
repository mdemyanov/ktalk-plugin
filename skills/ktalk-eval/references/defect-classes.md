# Catalogue of prompt defect classes

An append-only list of systemic defect classes of the analysis prompt (ADR-019 §1). When the
`ktalk-evaluator` agent finds a defect, it MUST take the `id` from this table. Finding no
matching class, it proposes a new row in the same commit that records the first occurrence.
Rows are never deleted and never reworded after the fact — only added.

The catalogue below sits in a fenced block because its `название` and `пример` columns are
verbatim Russian data, not prose: the evaluator copies them into the report and into the body
of a prompt-defect issue, where `CONTRIBUTING.md` (section `Заведение issue по дефекту промта`)
requires a 1:1 transfer without rephrasing. Translating or rewording a cell is a defect
(ADR-021 D2, FR-3 class 2).

```
| id | название | пример |
|---|---|---|
| completeness-prose-not-table | Обязательство названо прозой протокола (шапка, блок «Формат», основной текст), но не перенесено в таблицу «Договорённости» и не объяснено в «Открытых вопросах» | Status-встреча: «попутно — интерфейсный трек» в блоке «Формат», строки в таблице «Договорённости» нет, `commitments_count` при этом верен |
| confidence-high-by-request-mood | HIGH присвоен по дословной цитате реплики-запроса при отсутствии акта согласия в реплике-акцепте — наклонение запроса, а не сила акцепта, определило confidence | Запрос: «...сможешь рассказать?», акцепт — односложная реакция без явного акта согласия («Подумаю дополнительно») — оценщик проставил HIGH вместо MEDIUM |
| asr-name-marking-inconsistent | Искажённое ASR-имя не помечено маркером `[ASR?]`, либо резолвленное (исправленное) имя помечено маркером ошибочно | Имя в транскрипте искажено распознаванием речи, в протоколе перенесено как есть без `[ASR?]`; либо верно резолвленное имя несёт маркер `[ASR?]` без оснований |
```

When adding a class, append a row inside the block above, keeping the three columns and the
Russian wording of the last two.
