# demo-data Specification

## Purpose

TBD - created by archiving change 'demo-data'. Update Purpose after archive.

## Requirements

### Requirement: Demo data reads as a real Taiwanese clinic

Seed data SHALL be recognisable as clinical records from a Taiwanese clinic. Names SHALL be
Chinese, identifiers SHALL follow the local medical record number convention, and ages SHALL
be distributed the way a clinic's patient population is. Data that reads as obviously
synthetic redirects a viewer's attention from the product to the data.

#### Scenario: Patient names are Chinese

- **WHEN** the seeded patients are listed
- **THEN** every patient has a Chinese name composed of a family name and a given name, and
  none contains markup, placeholder text, or question marks

#### Scenario: Names exercise the CJK joining rule

- **WHEN** a seeded patient's name is rendered
- **THEN** the family and given parts appear with no separating space, confirming the joining
  rule against real data rather than only against fixtures

#### Scenario: Ages are plausible for a clinic

- **WHEN** the seeded patients are listed
- **THEN** their ages span a realistic range for outpatient care, and no patient shows an age
  of zero caused by a missing or defaulted birth date

#### Scenario: Every patient carries a record number

- **WHEN** a seeded patient is displayed
- **THEN** it carries an identifier in the local medical record number format, so the record
  number line is exercised rather than omitted

---
### Requirement: Vital signs form a trend, not isolated points

Seed data SHALL include vital-signs observations spanning at least 48 hours per patient, at
intervals a ward or clinic would actually record. A single reading per patient cannot
demonstrate a trend, and a trend is what this product exists to show.

#### Scenario: Each patient has a readable series

- **WHEN** a seeded patient's vital signs are retrieved
- **THEN** the response contains multiple observations across at least 48 hours, each carrying
  an effective time and a numeric value

#### Scenario: Observations use the vital-signs codes the app queries

- **WHEN** vital-signs observations are seeded
- **THEN** they carry LOINC codes and the `vital-signs` category, so the app's existing query
  finds them without special-casing

---
### Requirement: Some observations carry a reference range and fall outside it

Seed data SHALL include observations that carry a server-supplied `referenceRange`, and among
them SHALL include values that fall outside those bounds. Without this, the out-of-range slice
has nothing to show and the feature cannot be demonstrated or verified end to end.

#### Scenario: Out-of-range slice resolves to a real count

- **WHEN** the slice counts load against seeded data
- **THEN** the out-of-range card shows a positive count rather than an em dash

#### Scenario: Both sides of the boundary are represented

- **WHEN** the seeded observations are examined
- **THEN** some values fall outside their reference range and others fall within it, so the
  classification is demonstrated to discriminate rather than to mark everything

#### Scenario: Some observations deliberately carry no reference range

- **WHEN** the seeded data includes observations without a reference range
- **THEN** those are excluded from the out-of-range slice, demonstrating that the app declines
  to judge values the server did not bound

---
### Requirement: Seeding is repeatable

The seed script SHALL be safe to run more than once without creating duplicates, so a demo can
be reset and the data set can evolve without rebuilding the database.

#### Scenario: Running the script twice

- **WHEN** the seed script is run a second time against a server that already holds its data
- **THEN** the resulting record count is unchanged, and no resource is duplicated

#### Scenario: Reporting what it did

- **WHEN** the seed script completes
- **THEN** it reports how many resources of each type were created or already present, so a
  failure to seed is visible rather than silent

---
### Requirement: The same app connects to a second server unchanged

The app SHALL reach the seeded server through the same code path it uses for any other FHIR
server, with no build-time or source-level difference. "Connects to any FHIR server" is this
product's central claim, and a claim verified against exactly one server is not verified.

#### Scenario: Switching servers requires only a base URL

- **WHEN** the user selects the local server profile instead of the public sandbox
- **THEN** sign-in, patient listing and slice counts all work, using the same binary

#### Scenario: Capabilities the second server lacks degrade rather than break

- **WHEN** the app queries a resource type the server does not implement and receives an error
- **THEN** the affected part of the screen degrades on its own and the rest of the screen keeps
  working

---
### Requirement: Practitioner identifiers are stable across reseeds

Practitioners SHALL be created with identifiers chosen by the seed rather than assigned by the
server, so that a system outside the FHIR server can bind an account to a practitioner and
keep that binding after the data is loaded again.

The requirement is limited to practitioners because they are the resources external systems
reference by identity. Patients, encounters, observations and medication requests keep
server-assigned identifiers.

#### Scenario: Reseeding preserves practitioner identifiers

- **WHEN** the database is recreated and the seed is run again
- **THEN** each practitioner is reachable at the same identifier as before

#### Scenario: The identifier is predictable from the seed definition

- **WHEN** the seed defines a practitioner
- **THEN** the identifier that practitioner will occupy is derivable from that definition
  alone, without querying the server

#### Scenario: Seeding remains repeatable

- **WHEN** the seed runs a second time against a server that already holds the practitioners
- **THEN** the practitioner count is unchanged and no practitioner is duplicated
