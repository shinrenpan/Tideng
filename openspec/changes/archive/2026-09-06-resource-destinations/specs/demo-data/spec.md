## ADDED Requirements

### Requirement: Prescriptions carry dosage instructions in more than one shape

The seeded medication requests SHALL include dosage instructions in four distinct shapes, so that
a view rendering them is exercised against the cases that are actually hard rather than only the
convenient one.

Three of the four SHALL be cases where the record does not state specific clock times, because
those are the cases where an implementation is tempted to invent them:

- a frequency over a period with **no time of day** — the common case, and the one where the
  times a prescription means are set by institutional routine rather than by the record
- an **as-needed** instruction, which has no schedule at all
- a **sequence of instructions** on one prescription, expressing a dose that changes over time

The fourth SHALL state explicit times of day, as the contrasting case where the record does
answer the question.

#### Scenario: A frequency with no time of day is present

- **WHEN** the seeded data is inspected
- **THEN** at least one prescription states a frequency over a period and carries no time of day

#### Scenario: An as-needed prescription is present

- **WHEN** the seeded data is inspected
- **THEN** at least one prescription is marked as taken when needed

#### Scenario: A changing dose is present

- **WHEN** the seeded data is inspected
- **THEN** at least one prescription carries more than one dosage instruction, with the dose
  differing between them

#### Scenario: An explicitly timed prescription is present

- **WHEN** the seeded data is inspected
- **THEN** at least one prescription states times of day, so the contrast with the unspecified
  cases is visible in the same data set

#### Scenario: Every prescription still names its medication and requester

- **WHEN** the seeded data is inspected
- **THEN** each prescription still carries a medication and a requester, and the requester is a
  practitioner permitted to prescribe
