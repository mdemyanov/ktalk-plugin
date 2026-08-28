# Rubric for scoring ktalk protocol quality

Used by the `ktalk-evaluator` agent when scoring each protocol.

The ADR-018 revision (calibration of the analysis prompt layer, DEV-014): the rubric used not
to name three systemic defects explicitly — the operator found them by reading, not by the
rubric. Below they are named in the method of each dimension, not only in a general
"completeness" / "accuracy" formulation.

Russian literals in this file are quotations and protocol section names — the meeting is held
in Russian and the protocol is written in Russian, so they are reproduced verbatim (ADR-021).

---

## 1. Completeness — 1–5

Did every decision, agreement and status update from the transcript reach the protocol?

| Score | Criterion |
|-------|-----------|
| 5 | Every decision, agreement and status update from the transcript is in the protocol. Nothing is missing. The prose and the `Договорённости` table agree (see Method). |
| 4 | One minor topic or sub-point is missing, but every decision and agreement is present. |
| 3 | One decision or agreement is missing, **or** is named in the protocol's prose (the header, the `Формат` block, the body text) but was not carried into the `Договорённости` table and not explained in `Открытые вопросы`, **or** a whole discussion topic is covered too superficially. |
| 2 | Several decisions or agreements are missing. A whole line of discussion is absent. |
| 1 | The protocol covers less than half of what was discussed. |

**Method:**

1. A systematic pass over the transcript → list ALL decisions, agreements and statuses →
   check each one is present in the protocol.
2. **Internal consistency (prose vs table).** Separately from the comparison with the
   transcript — compare the protocol against itself: for every commitment named in the
   protocol's prose (including the header/frontmatter and the `Формат` block, not only the
   body text), check that a row of the `Договорённости` table corresponds to it, or that
   `Открытые вопросы` records explicitly why it is absent. A `commitments_count` matching the
   number of table rows does **not** confirm completeness — the counter counts table rows, and
   it also adds up when a commitment settled in the prose and never reached the table at all
   (observed: `попутно — интерфейсный трек` in the `Формат` block of a status-meeting
   protocol, with no row in the table and `commitments_count` nonetheless correct).

Ruling (do not dissolve into point 1, do not introduce a separate dimension): the scale does
not change — the wording "one decision or agreement is missing" already covers this case at
3/5. The defect was not in the numbers but in the method failing to say that this class of
omission must be looked for separately from the comparison with the transcript. The fix is the
method, point 2 above, plus the explicit mention in criterion 3/5, so that the evaluator does
not read "missing" as only "entirely absent from the protocol".

---

## 2. Accuracy — 1–5

Are the extracted facts correct? Is the attribution right (who said what)? Are the names
resolved correctly through the profile directory?

| Score | Criterion |
|-------|-----------|
| 5 | Every fact matches the transcript. Every attribution is correct. No invented content. Name resolution (see Method) is correct. |
| 4 | A minor paraphrase that shifts the meaning slightly, but no factual errors. |
| 3 | One factual error, a wrong attribution (wrong person, number, date), **or** a name marking that contradicts the resolution fact (a name matched exactly against the directory marked as unconfirmed, or an ASR-distorted name left clean with no marker). |
| 2 | Several factual errors, or a significant misattribution that changes the meaning. |
| 1 | Invented content (a hallucination) — decisions or agreements that never happened. |

**Method:** spot-check every decision, agreement, date, number and name. Any invented item = 1
automatically.

**Name resolution (FR-42 AC1).** For every proper name (a participant or a third party) met in
the protocol:

- Resolved unambiguously through the host project's profile directory → written in its
  corrected form, **without** the `[ASR?]` marker. A resolved name carrying the marker is a
  defect (false-positive uncertainty); count it as a factual error.
- Not resolved (absent from the directory, no directory declared, or an ambiguous partial
  match) → marked `[ASR?]`. An ASR-distorted name without the marker is a defect (missed
  uncertainty); count it as a factual error.

This is an error in the content of a particular name (Accuracy), not in the marker's form as a
schema element (that is §3 below) — a protocol where the same class of uncertainty is marked
inconsistently in both directions (an exact clean name marked, a distorted one not) cannot
score 5, even if every other fact is right.

---

## 3. Schema Consistency — 1–5

Does the output follow the expected protocol template?

| Score | Criterion |
|-------|-----------|
| 5 | Every mandatory section present. Frontmatter complete and correct. Confidence values stated. Timecodes present. The `[ASR?]` marker is of a single form and does not count towards `unclear_count`. `Ключевые тезисы` is present only when `meeting_type: session`. |
| 4 | Minor formatting problems (one optional section missing) **or** `Ключевые тезисы` present as an empty placeholder section instead of being absent entirely for a non-`session` type. |
| 3 | One mandatory section missing, frontmatter incomplete, **or** the uncertain-name marker appears in several forms in one document (`[ASR?]`, `[UNCLEAR: ...]`, `[ASR, ...]` mixed together). |
| 2 | Several structural deviations from the template. |
| 1 | The protocol does not follow the expected schema at all. |

**Method:** a checklist against the template in `agents/references/protocol-template.md`:

- [ ] Frontmatter: type, subtype, recording_id, title, date, duration_min, participants,
      source, transcript, decisions_count, commitments_count, unclear_count
- [ ] The `Участники` section
- [ ] The `Ключевые решения` section with the table
      `| # | Решение | Кто принял | Таймкод | Confidence |`
- [ ] The `Договорённости` section with the table
      `| Кто | Что | Срок | Confidence | Таймкод |`
- [ ] The `Открытые вопросы` section with `[UNCLEAR]` markers
- [ ] The `Флаги для владельца проекта` section (where applicable)
- [ ] The `Заметки` section with the source
- [ ] The `Ключевые тезисы` section — **only** for `meeting_type: session`; for every other
      meeting type it is absent **entirely** (not an empty section with a heading and no
      content)
- [ ] The uncertain-name marker is exactly `[ASR?]` (the form is fixed by
      `agents/references/protocol-template.md`; it is not invented on the spot by the
      evaluator or by the authoring model); a single form throughout the document, including
      repeated mentions of the same name (FR-42 AC4 — consistency within the document)
- [ ] `[ASR?]` is **not** counted in the frontmatter `unclear_count` — that counter counts
      only the `[UNCLEAR]` items of the `Открытые вопросы` section; the two tokens are never
      mixed in one number
- [ ] `[UNCLEAR]` (open questions) and `[ASR?]` (an uncertain name) are not confused with each
      other: `[UNCLEAR]` in place of a name, or `[ASR?]` inside `Открытые вопросы`, is a
      defect of form

---

## 4. Actionability — 1–5

Are the agreements concrete enough to be executed (WHO, WHAT, WHEN)?

| Score | Criterion |
|-------|-----------|
| 5 | Every agreement has an owner, a concrete action with a named object or area, and a deadline (or an explicit "no deadline stated"). |
| 4 | Every agreement has WHO and WHAT; 1–2 lack a deadline without an `[UNCLEAR]` flag. |
| 3 | Some agreements are vague (a verb with no object and no ownership — for example a bare `команда посмотрит` with no statement of what exactly) and are not flagged. |
| 2 | Several agreements have no owner or are too vague to execute. |
| 1 | The agreements section is unusable — no clear ownership or actions. |

**Method:** for each row of the `Договорённости` table check: is `Кто` a concrete person? Is
`Что` a concrete action **with a named object or area**? Is there a deadline, or an explicit
note that there is none?

A clarification of `Что` after ADR-018 (it removes the conflict with calibrated MEDIUM
commitments): a verb such as `покопать`, `обдумать`, `посмотреть` is not by itself an
Actionability defect if it has an object — `покопать по КЦП` or
`обдумать вопрос до понедельника`. The defect is a verb **without** an object and without ownership
(`команда посмотрит`, with no statement of what exactly). The execution confidence level
(`confidence`: HIGH/MEDIUM/LOW) is a separate dimension (§5 below); Actionability neither
penalises nor rewards it: the commitment `Покопать по КЦП` with `confidence: MEDIUM`
(Example 3b, `analysis-quality.md`) is a concrete action for the purposes of this dimension,
and MEDIUM does not turn it into a vague one.

---

## 5. Confidence Usage — 1–5

Do the confidence levels (HIGH/MEDIUM/LOW) match the actual evidence?

| Score | Criterion |
|-------|-----------|
| 5 | Confidence matches the evidence. HIGH = the accepting utterance carries an explicit act of agreement (not merely a verbatim quotation of the requesting utterance). MEDIUM = unambiguously inferred, or the acceptance is a one-word reaction with no act of agreement. `[UNCLEAR]` is used for unclear items. |
| 4 | One borderline assignment (e.g. MEDIUM where LOW would be more precise). |
| 3 | Confidence is missing in several places, **or** HIGH is used for clearly inferred content, **or** HIGH was assigned on the strength of a verbatim quotation of the requesting utterance with no act of agreement in the accepting one (the mood of the request, rather than the force of the acceptance, decided the confidence). |
| 2 | Systematic overrating — many items marked HIGH without support in the transcript. |
| 1 | No confidence annotations, or every item marked HIGH regardless of the evidence. |

**The modality of the request does not determine confidence — the accepting utterance does.**
A conditional construction in the requesting utterance (`может быть`, `если вдруг`,
`возможно`) is **not** by itself a defect and does not lower confidence if the acceptance is
unambiguous. The defect is assigning HIGH on the strength of a verbatim quotation of the
request without checking whether the accepting utterance carries an explicit act of agreement.

Reference pairs (anonymised down to the timecode — FR-41 AC1/AC2 of the requirement,
regression cases; they must yield the stated `confidence` under any revision of the prompt):

```
Запрос [00:46:54]: А ты можешь вот это вот, может быть, следующий понедельник здесь рассказать?
Акцепт [00:47:09]: Хорошо. […] Договорились.                                        → HIGH

Запрос [00:57:40]: Если вдруг ты найдёшь способ… может быть, даже просто по КЦП… Подумаю дополнительно
Акцепт [00:57:51]: Покопать.                                                        → MEDIUM
```

The first pair is HIGH because the acceptance carries an explicit act of agreement; the
conditionality of the request does not affect the outcome. The second is MEDIUM, not HIGH: a
one-word reaction with no act of agreement. The conditionality of the request is the same in
both — what tells the pairs apart is not the mood of the request but the force of the
acceptance.

The presence of a verbatim quotation is a necessary condition for HIGH but not a sufficient
one: the quotation must be of the acceptance carrying the act of agreement, not of the
request.

---

## Composite score

**Overall = (Completeness + Accuracy + Actionability + Confidence Usage) / 4**

Schema Consistency is reported separately ("format health").

Thresholds:

- **4.0+** — excellent, no rework needed
- **3.0–3.9** — acceptable, improvements possible
- **2.0–2.9** — rework needed
- **< 2.0** — serious quality problems

## Token Efficiency (a qualitative observation)

Not scored numerically. Recorded:

- Transcript length (characters)
- Protocol length (characters)
- Compression ratio (transcript / protocol)
- Observation: is the protocol too verbose or too terse?

---

## Verification method: reading the protocol vs an A/B run

Not every criterion above can be checked by reading one protocol — some are visible only when
two runs of the same recording under different prompt revisions are compared (A/B). The
division (source: the ADR-018 spec, §3 `Разграничение верификации`):

| What is checked | Method |
|---|---|
| §1 internal consistency of the prose and the `Договорённости` table | reading one protocol |
| §2 resolution of a particular name against the profile directory | reading one protocol + the profile directory |
| §3 the form of the `[ASR?]` marker, section composition and optionality | reading one protocol |
| §4 concreteness of WHO/WHAT/WHEN | reading one protocol |
| §5 confidence for a particular accepting utterance present in **this** recording | reading one protocol (a direct comparison with the recording's transcript) |
| Regression: the same transcript fragment yields a different confidence under a new prompt revision than under the old one | **only** an A/B comparison of two runs of one recording |
| Robustness of a fix across meeting types (not a one-off success on a single recording) | **only** an A/B comparison across several recordings |
| NFR-25 AC1 (a minor version bump when the prompt layer changes) | a static diff script (`check-plugin-composition.sh`), not this rubric |

The term "automatic check" used in the requirement's AC does not mean an existing automated
test: there is no automated test of prompt behaviour in this plugin, and by the ADR-012
boundary there cannot be one (the prompt layer is not covered by the `ktalk-mcp` package's
pytest suite). The verification method for each item is given by the table above: either
reading the protocol text (by a human or by an LLM evaluator), or comparing two A/B runs;
neither is a CI test in the usual sense.

## The plugin version in the report and the tracker (NFR-25 AC2)

The `ktalk-evaluator` report and the tracker row MUST carry the plugin version
(`.claude-plugin/plugin.json`, the `version` field) as of the run — not only the skill's
internal `prompt_version` (`skills/ktalk-registry/_meta.md`). These are two independent
counters and they have already diverged (the skill's `prompt_version` and the plugin version
in the operator's tracker disagreed, DEV-014): one grows when the text of a particular file is
edited, the other when anything under `agents/` or `skills/ktalk-registry/` is edited (which
need not coincide with editing the file that carries `prompt_version`).

- `plugin_version` — a mandatory frontmatter field of the report and a tracker column; the
  value is `version` from `.claude-plugin/plugin.json` as of the run (for example `1.3.0`).
- `prompt_version` — kept alongside; it is neither replaced by nor a substitute for
  `plugin_version`: they are different quantities (the skill's internal counter vs the plugin
  package version).

A report or a tracker row without `plugin_version` is an incomplete output contract of
`ktalk-evaluator` / `ktalk-eval` (the exact field format is in `agents/ktalk-evaluator.md` and
`skills/ktalk-eval/SKILL.md`); the field takes no part in the §3 scale of this rubric — §3
scores the meeting protocol against `protocol-template.md`, not the `ktalk-eval` report about
itself.
