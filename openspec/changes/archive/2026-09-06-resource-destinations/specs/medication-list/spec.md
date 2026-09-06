## ADDED Requirements

### Requirement: The medication view shows this patient's prescriptions

Opening a patient from the用藥中 slice SHALL present that patient's medication requests, each
showing the medication as recorded, the request status, and who requested it.

#### Scenario: Prescriptions are listed with their medication

- **WHEN** the medication view opens for a patient with active prescriptions
- **THEN** each prescription shows the medication the record names, its status, and its requester

#### Scenario: The patient has no prescriptions

- **WHEN** the server returns no medication requests for this patient
- **THEN** the view says so plainly rather than rendering an empty frame

### Requirement: Dosage instructions are reproduced, never expanded

A `MedicationRequest` may carry dosage instructions with a timing structure. The view SHALL
reproduce what the timing states — how many times, over what period — and SHALL NOT convert that
into concrete clock times.

The reason is that the conversion is not derivable from the record. A prescription of three
times daily with no times of day is a complete and valid instruction; which three times it means
is set by the institution's medication round schedule, which is not present in FHIR data.
Producing times would present an assumption as if it were the prescription.

#### Scenario: A frequency with no times of day

- **WHEN** a dosage instruction states a frequency over a period but carries no time of day
- **THEN** the view states the frequency as recorded and states that specific times were not
  specified, and no clock times appear

#### Scenario: A frequency with times of day

- **WHEN** a dosage instruction carries times of day
- **THEN** those times are shown, because they are in the record

#### Scenario: As-needed medication

- **WHEN** a dosage instruction is marked as taken when needed
- **THEN** it is shown as taken when needed, and no schedule is implied

### Requirement: Every dosage instruction on a prescription is shown

A prescription may carry more than one dosage instruction, which is how a changing dose over
time is expressed. The view SHALL show each instruction in the order the record gives, and SHALL
NOT collapse them to one.

Collapsing a sequence would hide exactly the information the sequence exists to carry.

#### Scenario: A prescription with a changing dose

- **WHEN** a medication request carries several dosage instructions
- **THEN** each is shown, in the recorded order

#### Scenario: A prescription with no dosage instruction

- **WHEN** a medication request carries no dosage instruction at all
- **THEN** the medication is still shown, with no dosage line and nothing invented in its place

### Requirement: The medication view offers no clinical judgement

Text in this view SHALL reproduce what the prescription records. It SHALL NOT suggest, question
or evaluate a prescription: no interaction warnings, no dose appraisal, no adherence assessment,
no wording that implies a prescription should change.

Stating "500 mg, three times daily" reproduces the record. Stating that a dose is high,
duplicated, or due for review is a clinical judgement, and this app does not make one.

#### Scenario: Wording contains no appraisal

- **WHEN** any string in the medication view is read
- **THEN** it names a field or reproduces a recorded value, and evaluates nothing

#### Scenario: Two prescriptions that a clinician might question

- **WHEN** a patient carries prescriptions that a clinician might consider related or duplicated
- **THEN** they are listed as recorded, with no marking, grouping or warning that draws a
  conclusion about them
