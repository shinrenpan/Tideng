## ADDED Requirements

### Requirement: The record view shows the patient resource itself

Opening a patient from the全部病人 slice SHALL present that patient's own record: display name,
administrative gender, birth date with the derived age, and the identifiers the server supplies.

This view exists to show what the FHIR `Patient` resource actually contains, so every field it
renders SHALL come from the resource rather than from an assumption about what a patient record
usually holds.

#### Scenario: Identity fields are shown as recorded

- **WHEN** the record view opens for a patient the server returned
- **THEN** the name, gender and birth date shown are the values in the resource, with the age
  derived from the birth date rather than stored separately

#### Scenario: Absent fields are omitted

- **WHEN** the patient has no birth date
- **THEN** neither a birth date nor an age is shown, and no placeholder text stands in for them

### Requirement: Identifiers are distinguished by what they are for

A `Patient` carries several identifiers and they do not mean the same thing. The view SHALL
label each identifier it shows by its type rather than listing raw values, and SHALL NOT present
an internal key as if it were a medical record number.

An identifier the app cannot characterise SHALL be omitted rather than shown unlabelled, because
an unexplained number invites the reader to assume it is the one they recognise.

#### Scenario: The medical record number is identified as such

- **WHEN** the patient carries an identifier typed as a medical record number
- **THEN** it is shown labelled as the record number

#### Scenario: A seeding key is not shown as a record number

- **WHEN** the patient carries an identifier that is not typed as a medical record number
- **THEN** that value is not presented as the record number

#### Scenario: No typed record number at all

- **WHEN** none of the patient's identifiers is typed as a medical record number
- **THEN** the record number line is absent entirely

### Requirement: The national identifier is shown when the server supplies it

Taiwanese patient records carry a national identification number in a nationally defined
identifier system. When the server supplies it, the view SHALL show it labelled as such.

When it is absent the line SHALL be omitted. The app SHALL NOT derive, reconstruct or validate
the number — displaying a value the server did not send would be inventing an identifier for a
real person.

#### Scenario: The identifier is present

- **WHEN** the patient carries an identifier in the national identification system
- **THEN** it is shown, labelled as the national identifier

#### Scenario: The identifier is absent

- **WHEN** the patient carries no identifier in that system
- **THEN** no national identifier line appears, and nothing is derived to fill the gap

### Requirement: The record view states facts and never characterises the patient

Text in this view SHALL describe what the record contains. It SHALL NOT characterise the person
or their condition — no risk wording, no summary of health status, no derived category.

#### Scenario: Wording contains no judgement

- **WHEN** any string in the record view is read
- **THEN** it names a field or reproduces a recorded value, and asserts nothing about the
  patient's health
