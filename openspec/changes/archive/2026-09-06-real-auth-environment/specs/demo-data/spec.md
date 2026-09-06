## ADDED Requirements

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
