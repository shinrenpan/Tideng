## ADDED Requirements

### Requirement: List rows open the patient

Each row SHALL be selectable and SHALL open that patient's detail view. Rows SHALL be visibly
actionable so the affordance is discoverable rather than hidden.

#### Scenario: Selecting a row opens the detail

- **WHEN** the user selects a patient row
- **THEN** that patient's detail view opens, identified by the patient the row represents

#### Scenario: The selection crosses the feature boundary as primitives

- **WHEN** the detail view is constructed from a list selection
- **THEN** it receives only primitive values, not the list's domain model
