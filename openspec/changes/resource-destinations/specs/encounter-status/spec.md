## ADDED Requirements

### Requirement: The encounter view shows this patient's visits

Opening a patient from the今日就診 slice SHALL present that patient's encounters, most recent
first, each showing its status, its class, when it started, and when it ended.

#### Scenario: Encounters are ordered by when they began

- **WHEN** the encounter view opens for a patient with more than one encounter
- **THEN** they are listed with the most recently started first

#### Scenario: The patient has no encounters

- **WHEN** the server returns no encounters for this patient
- **THEN** the view says so plainly, and does not render an empty frame that looks like a
  loading failure

### Requirement: An encounter with no end is presented as still open

In FHIR an encounter whose period has a start but no end means the visit has not finished, or
that its end was never recorded. The view SHALL present such an encounter as still open rather
than showing an empty end time or substituting the current time.

Substituting a value would assert something the record does not say. The distinction matters
because the same absence drives search behaviour: an open-ended period matches date searches
that reach into the future.

#### Scenario: An open encounter

- **WHEN** an encounter has a period start but no period end
- **THEN** it is shown as still open, and no end time is displayed

#### Scenario: A finished encounter

- **WHEN** an encounter has both a period start and a period end
- **THEN** both times are shown

#### Scenario: No period at all

- **WHEN** an encounter carries no period
- **THEN** neither a start nor an end is shown, and the encounter is not claimed to be open —
  the record simply does not say when it happened

### Requirement: The recorded status is shown, not inferred from the period

`Encounter.status` and `Encounter.period` are separate facts and can disagree. The view SHALL
show the status the server recorded, and SHALL NOT overwrite it with a status derived from
whether the period has an end.

#### Scenario: Status and period disagree

- **WHEN** an encounter's status says finished but its period has no end
- **THEN** the status shown is the recorded one, and the period is shown as it stands

### Requirement: The participating practitioner is resolved when the server allows it

An encounter names its participants by reference. The view SHALL resolve those references to
practitioner names when the server returns them, and SHALL degrade to the reference itself when
it cannot — an unresolved reference is still more informative than a blank.

Failure to resolve a participant SHALL NOT prevent the encounter from being shown.

#### Scenario: The practitioner resolves

- **WHEN** an encounter names a practitioner participant and that practitioner can be retrieved
- **THEN** the practitioner's name is shown

#### Scenario: The practitioner cannot be retrieved

- **WHEN** the practitioner reference cannot be resolved
- **THEN** the encounter is still shown, with the reference in place of a name

### Requirement: The encounter view states facts and never characterises the visit

Text in this view SHALL reproduce recorded values and name fields. It SHALL NOT describe a visit
as routine, urgent, concerning or overdue, and SHALL NOT derive any such category.

#### Scenario: Wording contains no judgement

- **WHEN** any string in the encounter view is read
- **THEN** it names a field or reproduces a recorded value, and characterises nothing
