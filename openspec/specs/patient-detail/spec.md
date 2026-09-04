# patient-detail Specification

## Purpose

TBD - created by archiving change 'patient-detail-vitals'. Update Purpose after archive.

## Requirements

### Requirement: Detail shows who the patient is

The detail view SHALL identify the patient using the same rules as the list: display name,
administrative gender, age when derivable, and record number when the server marks one.
Values that are absent SHALL be omitted rather than filled with placeholders.

#### Scenario: Identity carries over from the list

- **WHEN** a patient is opened from the list
- **THEN** the detail view shows the same name, gender, age and record number the list showed,
  with no re-interpretation

#### Scenario: Missing fields are omitted

- **WHEN** the patient has no birth date and no record number
- **THEN** neither an age nor a record number is shown, and no empty rows are rendered

---
### Requirement: Vital signs are shown as a time series

The detail view SHALL plot each kind of vital sign over time rather than showing only the
latest value. A single number cannot show whether a patient is improving or deteriorating,
which is the question the view exists to answer.

#### Scenario: One chart per kind

- **WHEN** a patient has observations of several kinds
- **THEN** each kind is charted separately, labelled with its name and unit

#### Scenario: Points are ordered by time regardless of server ordering

- **WHEN** the server returns observations in an arbitrary order
- **THEN** the chart plots them in chronological order

##### Example: Ordering independent of response order

| Response order (by time) | Plotted order |
| ------------------------ | ------------- |
| 09:00, 03:00, 21:00      | 21:00, 03:00, 09:00 |

#### Scenario: A single reading still renders

- **WHEN** a kind has exactly one observation
- **THEN** that kind renders as a single point rather than an empty or broken chart

#### Scenario: Observations without a usable value or time are excluded

- **WHEN** an observation carries no numeric value, or no time
- **THEN** it is not plotted, because a point needs both coordinates

---
### Requirement: Reference ranges are drawn as bounds, never as verdicts

When the server supplies a reference range, the chart SHALL depict those bounds so the reader
can see where values sit relative to them. The app SHALL NOT mark any individual point as
abnormal, colour it by severity, or attach any wording that interprets it.

#### Scenario: Server-supplied bounds are drawn

- **WHEN** the observations for a kind carry a reference range
- **THEN** the chart shows that range as a band, and the values are drawn against it

#### Scenario: No range means no band

- **WHEN** the observations for a kind carry no reference range
- **THEN** the chart draws the values with no band, and does not substitute any built-in range

#### Scenario: Points outside the band are not singled out

- **WHEN** a value falls outside the drawn band
- **THEN** that point is rendered exactly like every other point, with no distinct colour,
  icon, or label — the band already makes its position visible

#### Scenario: No interpretive wording anywhere in the view

- **WHEN** the detail view renders
- **THEN** no text describes a value as abnormal, high, low, concerning, or suspected, and no
  text recommends any action

---
### Requirement: The vital signs section handles four states

The section SHALL distinguish loading, loaded-but-empty, failure, and content, deciding by
content first and status second so that a failed refresh never replaces charts already shown.

#### Scenario: Patient has no recorded vital signs

- **WHEN** the request succeeds and returns no observations
- **THEN** the section states that none are recorded, distinct from a loading or failed state

#### Scenario: Loading fails on first entry

- **WHEN** the request fails and no observations are on screen
- **THEN** the section shows the failure with a control that retries

#### Scenario: Refresh fails while charts are on screen

- **WHEN** charts are already displayed and a refresh fails
- **THEN** the charts remain and the failure is surfaced without clearing them

---
### Requirement: Returning to the list preserves its state

Navigating back from the detail view SHALL return to the list as it was left, including its
slice, scroll position and any keyword in effect.

#### Scenario: Keyword survives the round trip

- **WHEN** the user filters the list by keyword, opens a patient, and navigates back
- **THEN** the keyword is still applied and the same filtered patients are shown
