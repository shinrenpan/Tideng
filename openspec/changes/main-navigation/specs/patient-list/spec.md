## ADDED Requirements

### Requirement: Patient list queries by slice

The patient list SHALL accept a slice that determines which patients are fetched, and SHALL name the active slice in its title so the user knows which subset is on screen.

#### Scenario: All patients

- **WHEN** the list is opened with the all-patients slice
- **THEN** it fetches patients without an additional filter and titles itself for that slice

#### Scenario: Seen today

- **WHEN** the list is opened with the seen-today slice
- **THEN** it fetches only patients who have an encounter dated today, and titles itself for that slice

#### Scenario: On active medication

- **WHEN** the list is opened with the active-medication slice
- **THEN** it fetches only patients who have at least one active medication request, and titles itself for that slice

#### Scenario: Outside reference range

- **WHEN** the list is opened with the out-of-range slice
- **THEN** it fetches only patients having at least one observation whose value falls outside a server-supplied reference range, and titles itself for that slice

### Requirement: Patient list filters by keyword

The list SHALL let the user narrow the fetched patients by keyword, matching against both the display name and the record number. Filtering SHALL happen without issuing a new request.

#### Scenario: Keyword matches a name

- **WHEN** the user types a keyword contained in a patient's name
- **THEN** the list shows only the matching patients

#### Scenario: Keyword matches a record number

- **WHEN** the user types a keyword contained in a patient's record number
- **THEN** that patient remains listed even though the keyword does not appear in the name

#### Scenario: Keyword matches nothing

- **WHEN** the keyword matches no fetched patient
- **THEN** the list indicates that no result matches the search, and the fetched patients are not discarded

### Requirement: Patient list presents four states in the correct order

The list SHALL decide what to render by first checking whether it has content, and only then by request status. Content already on screen SHALL NOT be replaced by a loading or error state.

#### Scenario: First load with no content yet

- **WHEN** the list has no patients and a request is in flight
- **THEN** it shows a loading indicator

#### Scenario: Load succeeded but the server returned nothing

- **WHEN** the request completed successfully and returned no patients
- **THEN** the list states that this server has no patients, distinct from the loading state

#### Scenario: Refresh fails while content is on screen

- **WHEN** the list already shows patients and a refresh request fails
- **THEN** the existing patients remain visible and the failure is surfaced without clearing them

#### Scenario: First load fails

- **WHEN** the list has no patients and the request fails
- **THEN** it shows the failure with a control that retries the same request

### Requirement: Patient rows present identity without interpretation

Each row SHALL show the patient's display name, administrative gender, age when derivable, and record number when present. Missing values SHALL be omitted rather than shown as empty fields.

#### Scenario: Chinese name joining

- **WHEN** a patient has family "王" and given "小明" and no text element
- **THEN** the row shows "王小明" with no separating space

#### Scenario: Western name joining

- **WHEN** a patient has family "Smith" and given "John" and no text element
- **THEN** the row shows "John Smith" with a separating space

#### Scenario: Server-supplied display text wins

- **WHEN** the name carries a text element
- **THEN** the row shows that text verbatim, without recomposing it from the family and given parts

#### Scenario: Partial birth date precision

- **WHEN** a patient's birth date carries only a year
- **THEN** the row shows an age derived from the year difference alone, without inventing a month or day

##### Example: Age derivation

| Birth date  | Today      | Age shown |
| ----------- | ---------- | --------- |
| 1958-03-14  | 2026-09-03 | 68        |
| 1958-11-14  | 2026-09-03 | 67        |
| 1989        | 2026-09-03 | 37        |
| absent      | 2026-09-03 | omitted   |

#### Scenario: Patient has no usable name

- **WHEN** a patient resource carries no name at all
- **THEN** the row shows a neutral placeholder and the remaining fields still render

#### Scenario: Patient without an identifier

- **WHEN** a patient resource carries no identifier
- **THEN** the row omits the record number rather than showing an empty separator
