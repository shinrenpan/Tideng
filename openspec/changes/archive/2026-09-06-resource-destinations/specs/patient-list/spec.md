## MODIFIED Requirements

### Requirement: List rows open the patient

Each row SHALL be selectable and SHALL open a detail view for that patient. Rows SHALL be visibly
actionable so the affordance is discoverable rather than hidden.

**Which** detail view opens SHALL be determined by the slice the list was reached through, because
the slice states what the user came to find out. A list reached from出參考值 answers a question
about values; a list reached from用藥中 answers a question about medication. Opening the same
view from every slice discards that intent and leaves the user to remember why they tapped.

#### Scenario: Selecting a row opens the detail

- **WHEN** the user selects a patient row
- **THEN** a detail view for that patient opens, identified by the patient the row represents

#### Scenario: The destination follows the slice

- **WHEN** the user selects a row in a list reached from a given slice
- **THEN** the view that opens is the one belonging to that slice: the patient record for全部病人,
  the encounter view for今日就診, the medication view for用藥中, and the vital signs view for
  超出參考值

#### Scenario: The selection crosses the feature boundary as primitives

- **WHEN** a detail view is constructed from a list selection
- **THEN** it receives only primitive values, not the list's domain model
