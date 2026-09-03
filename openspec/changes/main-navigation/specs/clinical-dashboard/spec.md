## ADDED Requirements

### Requirement: Sidebar shows the signed-in practitioner

The sidebar header SHALL identify the signed-in practitioner by name and role. The identity SHALL be resolved from the FHIR server using the reference carried in the id_token's fhirUser claim. When the server does not supply a usable name, the app SHALL fall back to displaying the raw reference rather than showing an empty header.

#### Scenario: Name and role both available

- **WHEN** the practitioner resource has a HumanName and an associated PractitionerRole carries a role code with display text
- **THEN** the sidebar header shows the practitioner's name on the first line and the role display text on the second line

#### Scenario: Name available but no role

- **WHEN** the practitioner resource has a HumanName but no PractitionerRole is returned
- **THEN** the sidebar header shows the name and omits the role line entirely, leaving no blank placeholder

#### Scenario: Practitioner cannot be resolved

- **WHEN** the practitioner read fails, or the returned resource carries no usable name
- **THEN** the sidebar header shows the raw reference (for example "Practitioner/137594487") and the app remains fully usable

#### Scenario: Name follows the same joining rule as patients

- **WHEN** a practitioner name has family "王" and given "大明" and no text element
- **THEN** the header shows "王大明" with no separating space

### Requirement: Sidebar presents top-level categories

The sidebar SHALL present the available top-level categories between the header and the footer. Categories that are not implemented SHALL NOT appear as placeholder rows.

#### Scenario: Category selection drives the content area

- **WHEN** the user selects a category in the sidebar
- **THEN** the content area shows the slice cards belonging to that category, and the selected row is visually marked as current

#### Scenario: Only implemented categories are listed

- **WHEN** the sidebar renders
- **THEN** it lists exactly the categories that have working content, and shows no rows labelled as planned or unimplemented

### Requirement: Sidebar footer identifies the connected server

The sidebar footer SHALL show which server the session is connected to, the practitioner reference, and a sign-out control.

#### Scenario: Signing out returns to the sign-in screen

- **WHEN** the user activates the sign-out control
- **THEN** the stored credentials are cleared and the app returns to the server entry screen

### Requirement: Content area presents patient slices as cards

The content area SHALL present the selected category's entries as a grid of cards. For the patients category, each card SHALL represent a different slice of the same patient population, not a different resource type. Each card SHALL show a count of patients in that slice.

#### Scenario: Patient slices are offered

- **WHEN** the patients category is selected
- **THEN** the grid shows cards for all patients, patients seen today, patients with values outside their reference range, and patients on active medication

#### Scenario: Card carries a count

- **WHEN** a slice's count has been resolved
- **THEN** that card shows the number of patients in the slice alongside the slice name

### Requirement: Slice counts resolve independently

Each slice count SHALL be requested and reported independently. The content area SHALL become visible before any count has resolved, and a failure in one count SHALL NOT prevent the others from displaying.

#### Scenario: Cards appear before counts resolve

- **WHEN** the content area is first shown
- **THEN** all cards are visible immediately, each showing its own loading indicator in place of a count

#### Scenario: One slow count does not block the others

- **WHEN** three counts have resolved and the fourth is still loading
- **THEN** the three resolved cards show their numbers and the fourth continues to show its loading indicator

#### Scenario: One failed count does not break the grid

- **WHEN** a count request fails
- **THEN** that card indicates its count is unavailable, the other cards keep their values, and the card remains tappable

### Requirement: Out-of-range determination uses only server-supplied ranges

The out-of-range slice SHALL classify an observation as outside its reference range only when the observation itself carries a reference range from the server. The app SHALL NOT apply built-in reference values, because defining what counts as normal is clinical judgement rather than a statement of fact.

#### Scenario: Observation carries a reference range

- **WHEN** an observation has a numeric value and a reference range with a low or high bound, and the value falls outside those bounds
- **THEN** the observation's patient is counted in the out-of-range slice

##### Example: Value against supplied bounds

| Observation value | Reference range | Counted as out of range |
| ----------------- | --------------- | ----------------------- |
| 38.9              | 36.0 – 37.5     | Yes                     |
| 37.0              | 36.0 – 37.5     | No                      |
| 35.2              | low 36.0 only   | Yes                     |
| 38.9              | none supplied   | No                      |

#### Scenario: Observation carries no reference range

- **WHEN** an observation has a numeric value but the server supplied no reference range
- **THEN** the observation is not classified in either direction and its patient is not counted in the out-of-range slice

#### Scenario: Server supplies no ranges at all

- **WHEN** no observation in the response carries a reference range
- **THEN** the out-of-range card shows a count of zero rather than an error

### Requirement: A malformed entry must not discard the whole response

The app SHALL tolerate individual resources that fail to decode, because real FHIR servers
return data that does not conform to the specification. A response SHALL be considered usable
as long as at least part of it decodes. A count derived by counting decoded entries SHALL be
reported as a lower bound whenever any entry was skipped; a count taken from a
server-reported total SHALL NOT, because that total describes what the server holds rather
than what this client managed to parse.

#### Scenario: One malformed resource among many

- **WHEN** a response contains 307 resources and one of them fails to decode
- **THEN** the remaining 306 are used, and the count for that slice is presented as a lower bound

#### Scenario: Entry-derived counts stay honest about being incomplete

- **WHEN** a slice count is obtained by counting decoded entries and any entry was skipped
- **THEN** the count is marked as a lower bound rather than presented as exact, so the
  displayed number never claims to be a total it cannot guarantee

#### Scenario: A server-reported total survives local decoding failures

- **WHEN** the server reports a total of 307 and one entry fails to decode locally
- **THEN** the count is still reported as exactly 307, because the total describes the server's
  data rather than this client's parsing

#### Scenario: Nothing decodes at all

- **WHEN** every entry in a response fails to decode
- **THEN** the slice reports its count as unavailable rather than reporting zero, because zero
  would be indistinguishable from "this server genuinely has none"

### Requirement: Selecting a card opens the corresponding patient list

Selecting a slice card SHALL open the patient list with that slice's filter already applied, and the list SHALL identify which slice is being shown.

#### Scenario: Slice filter carries into the list

- **WHEN** the user selects the patients-seen-today card
- **THEN** the patient list opens showing only patients with an encounter today, and its title names that slice

#### Scenario: Returning to the grid

- **WHEN** the user navigates back from a patient list
- **THEN** the slice grid is shown again with its previously resolved counts intact

### Requirement: User-facing text states facts and never clinical judgement

Every user-facing string in this capability SHALL describe an observable fact. The app SHALL NOT present interpretation, severity, or recommended action, because doing so moves the product from a record-keeping tool toward a regulated medical device.

#### Scenario: Out-of-range slice is named factually

- **WHEN** the out-of-range card is displayed
- **THEN** its label states that values fall outside the reference range, and does not use words such as abnormal, suspected, concerning, or any recommendation to act
