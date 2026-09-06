# auth-environment Specification

## Purpose

TBD - created by archiving change 'real-auth-environment'. Update Purpose after archive.

## Requirements

### Requirement: The environment authenticates people, it does not simulate it

`Server/` is the reference implementation of the environment the app expects to meet in
production. It SHALL therefore require real credentials: signing in SHALL present a login page
served by the authorization server, and SHALL succeed only when a username and password that
the environment holds are supplied.

Choosing an identity from a list without proving it SHALL NOT be a supported path.

#### Scenario: Signing in requires a password

- **WHEN** a user reaches the authorization server's login page
- **THEN** the page asks for a username and a password, and no combination of navigation
  reaches an authenticated session without supplying them

#### Scenario: Wrong credentials do not authenticate

- **WHEN** a user submits a username that exists with an incorrect password
- **THEN** the login page reports the failure and no authorization code is issued

---
### Requirement: The FHIR server rejects requests it cannot verify

The FHIR server SHALL verify the signature and issuer of the bearer token on every request,
using keys published by the authorization server. A request carrying no token, an expired
token, or a token signed by anything else SHALL be refused.

This is the negative path the previous environment could not exercise, because it accepted
every request.

#### Scenario: No token

- **WHEN** a FHIR request arrives with no Authorization header
- **THEN** the server refuses it with an unauthorized status and returns no resource data

#### Scenario: A token the server cannot verify

- **WHEN** a FHIR request carries a syntactically valid token signed by a key the issuer does
  not publish
- **THEN** the server refuses it with an unauthorized status

#### Scenario: A token from another issuer

- **WHEN** a FHIR request carries a token whose issuer differs from the configured one
- **THEN** the server refuses it with an unauthorized status

---
### Requirement: Accounts are bound to practitioners in the clinical data

Each account in the environment SHALL correspond to one `Practitioner` resource held by the
FHIR server, and the authorization server SHALL express that correspondence as the `fhirUser`
claim of the `id_token`, in the form `Practitioner/<id>`.

The binding SHALL survive reseeding: re-running the seed SHALL NOT change the identifiers the
accounts are bound to.

#### Scenario: Signing in yields a resolvable practitioner

- **WHEN** a user signs in with an account belonging to the environment
- **THEN** the `id_token` carries a `fhirUser` claim naming a `Practitioner` that the FHIR
  server can return

#### Scenario: The binding survives a reseed

- **WHEN** the demo data is seeded again after the database is recreated
- **THEN** the `Practitioner` identifiers named by the accounts resolve to the same people as
  before, with no change to the authorization server's configuration

#### Scenario: Accounts cover more than one role

- **WHEN** two accounts belonging to practitioners with different roles sign in
- **THEN** each resolves to its own practitioner, and the role shown differs accordingly

---
### Requirement: The environment starts from one command in one directory

Bringing the environment up SHALL require a single compose invocation from `Server/`, and
SHALL NOT require starting services from another repository first.

Loading demo data remains a separate step, because it is a data operation rather than part of
standing the environment up.

#### Scenario: A fresh start

- **WHEN** an operator runs the compose up command in `Server/` on a machine where none of the
  services are running
- **THEN** the authorization server, the FHIR server and the database all become reachable
  without any further command in another directory

#### Scenario: Restarting one service

- **WHEN** the FHIR server needs to be restarted to pick up a change
- **THEN** it can be restarted through compose, without terminating processes by hand

---
### Requirement: Addresses are configuration, not constants

The host names and the issuer URL used by the environment SHALL come from configuration, and
SHALL NOT be written into committed files as fixed values.

The reason is specific: the authorization server records its issuer URL inside every token it
signs, so an address that is fixed in place cannot be changed later without reissuing
configuration and invalidating tokens already held.

#### Scenario: Running at a different address

- **WHEN** the environment is brought up with a different host name supplied by configuration
- **THEN** discovery, the login page and token verification all use that host name, with no
  edit to a committed file

#### Scenario: Defaults are supplied

- **WHEN** an operator brings the environment up without supplying configuration
- **THEN** a documented default is used, so first-run does not require decisions

---
### Requirement: The environment holds no real patient data

The environment SHALL contain only generated demo data. No recording of a real person SHALL be
loaded into it, and the accounts SHALL belong to invented practitioners.

#### Scenario: What the environment contains

- **WHEN** the environment is seeded
- **THEN** every patient, practitioner and observation in it came from the seed, and none
  describes a real person
