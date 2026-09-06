# smart-authentication Specification

## Purpose

TBD - created by archiving change 'real-auth-environment'. Update Purpose after archive.

## Requirements

### Requirement: Discovery rejects a server that cannot support the flow

The client SHALL read `{base}/.well-known/smart-configuration` and SHALL refuse to begin
authorization when the document does not describe the flow the app performs. The refusal
SHALL happen before the browser opens, so the user is never asked for credentials on a server
that cannot complete the exchange.

The document SHALL be treated as unusable when it omits `authorization_endpoint`,
`token_endpoint`, or `code_challenge_methods_supported`, when `capabilities` omits
`launch-standalone` or `client-public`, or when `code_challenge_methods_supported` omits
`S256`.

#### Scenario: A field the flow depends on is missing

- **WHEN** the discovery document omits `authorization_endpoint`, `token_endpoint`, or
  `code_challenge_methods_supported`
- **THEN** discovery fails with a message naming the server as the cause, and no browser
  session is started

#### Scenario: The server does not offer standalone launch for public clients

- **WHEN** the discovery document parses but `capabilities` omits `launch-standalone` or
  `client-public`
- **THEN** authorization is refused before the browser opens, with a message that identifies
  the missing capability rather than blaming the user's input

#### Scenario: The reference environment satisfies discovery

- **WHEN** discovery runs against the environment described by the `auth-environment`
  capability
- **THEN** every field above is present and the app proceeds to authorization

---
### Requirement: The app never receives the user's credentials

Authentication SHALL be performed by the authorization server in a browser session. The app
SHALL NOT present a password field, SHALL NOT transmit a password, and SHALL NOT store one.
The only credential material the app holds SHALL be the tokens returned by the token endpoint.

#### Scenario: Signing in

- **WHEN** the user starts sign-in
- **THEN** the app opens the authorization server's page in a browser session and receives
  only an authorization code on return

#### Scenario: What the app retains

- **WHEN** the token exchange succeeds
- **THEN** the app stores only the token set, and no field of the stored data contains a
  password

---
### Requirement: The identity claim is verified before it is trusted

The identity shown to the user and used to build the practitioner reference comes from the
`fhirUser` claim of the `id_token`. The client SHALL verify the token's signature against the
issuer's published keys before reading any claim from it, and SHALL verify that the token's
issuer matches the one named by the discovery document.

An `id_token` that fails verification SHALL NOT contribute an identity. The session SHALL
remain usable, because authorization is decided by the resource server against the access
token, not by this claim.

#### Scenario: A valid token supplies the identity

- **WHEN** the `id_token` signature verifies against the issuer's keys and the issuer matches
  discovery
- **THEN** `fhirUser` is read and the practitioner reference is built from it

#### Scenario: A forged token supplies nothing

- **WHEN** the `id_token` signature does not verify, or its issuer differs from the one named
  by discovery
- **THEN** no identity is derived from it, and the app does not display a practitioner name or
  role that came from that token

#### Scenario: A failed identity does not end the session

- **WHEN** `id_token` verification fails but the access token is accepted by the FHIR server
- **THEN** clinical data continues to load, and the identity area degrades to what remains
  available rather than signing the user out

#### Scenario: No id_token at all

- **WHEN** the token response contains no `id_token`
- **THEN** the app proceeds without an identity rather than treating the sign-in as failed

---
### Requirement: Rejection by the resource server is handled as rejection

A server that verifies tokens SHALL be expected to reject the app. The client SHALL treat an
unauthorized response as an authentication outcome, not as a data error: it SHALL attempt a
single refresh when a refresh token is held, and SHALL return the user to sign-in when no
refresh is possible or the refresh itself is rejected.

#### Scenario: Access token expired, refresh available

- **WHEN** a FHIR request is answered with an unauthorized status and a refresh token is held
- **THEN** the client refreshes once and retries the request, and the user sees no
  interruption

#### Scenario: Refresh is itself rejected

- **WHEN** the refresh request is answered with an error
- **THEN** the stored tokens are discarded and the user is returned to sign-in

#### Scenario: No refresh token was granted

- **WHEN** a FHIR request is answered with an unauthorized status and no refresh token is held
- **THEN** the user is returned to sign-in rather than seeing an empty screen or a generic
  network error
