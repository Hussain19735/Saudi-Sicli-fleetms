# SharePoint Vehicles Field Mapping (Stage 1)

Status: design-only mapping. No production SharePoint connection or data writes are performed by this document.

## Scope and safety rules

- Initial SharePoint rollout is read-only for the Vehicles list.
- PostgreSQL remains the existing application data store until a separately approved migration plan exists.
- Do not infer or grant access from browser parameters.
- Actor identity and role must be derived from the authenticated server-side session.
- Records missing required scope are denied by default.
- No engine-number field is introduced.
- No production records are created, updated, or deleted by this stage.

## Existing PostgreSQL vehicle fields

The current `Fleetms.VehicleManagement.Vehicle` resource declares:

| PostgreSQL attribute | Proposed SharePoint internal field | Type / notes |
|---|---|---|
| id | FleetVehicleId | Text; preserve stable application ID |
| name | Title | Text; SharePoint display title |
| model_code | ModelCode | Text |
| category | Category | Choice/text; normalize against application enum |
| type | VehicleType | Choice/text; required |
| body_style | BodyStyle | Choice/text |
| chassis_number | ChassisNumber | Text |
| license_plate | LicensePlate | Text |
| vin | VIN | Text |
| year | ModelYear | Number |
| base_price | BasePrice | Currency/number; optional |
| purchase_date | PurchaseDate | Date |
| purchase_price | PurchasePrice | Currency/number; optional |
| dealer_name | DealerName | Text |
| color | Color | Text |
| hours | OperatingHours | Number |
| image_url | ImageUrl | Hyperlink/text; optional |
| mileage | Mileage | Number; default 0 in PostgreSQL |
| status | VehicleStatus | Choice/text; normalize against application enum |
| photo | PhotoReference | Text/reference only; binary content belongs in a document library |
| created_at | CreatedAt | Date/time; system/audit field |
| updated_at | UpdatedAt | Date/time; system/audit field |

## Required SharePoint scope fields

These fields are required for server-side filtering/authorization in the first rollout:

| SharePoint field | Type | Rule |
|---|---|---|
| ProjectId | Text or lookup ID | Required when the vehicle belongs to a project |
| CityId | Text or lookup ID | Required when the vehicle is assigned to a city |
| VehicleId | Text | Stable unique application identifier; must not rely on SharePoint list item ID alone |

A vehicle record must have at least one valid scope dimension (ProjectId or CityId) for maintenance-team/finance scope checks. Employee access additionally requires a trusted server-side vehicle assignment. Missing or malformed scope means deny/exclude.

## Account and role compatibility findings

The current account resource stores `roles` as an array of atoms. The current enum includes legacy roles such as `admin`, `technician`, and `driver`; the SharePoint access policy currently uses `company_admin`, `maintenance_team`, and `employee`.

No confirmed persisted user-to-project, user-to-city, or user-to-vehicle grant model was found in the reviewed user and profile resources. UserProfile contains profile/contact/location attributes, but a profile city string is not an authorization grant.

Before enabling SharePoint reads in a user-facing screen, implement and test a server-only actor resolver that:
1. Reads the authenticated user and organization from the server session.
2. Maps legacy roles explicitly to canonical roles (including handling multiple roles deterministically).
3. Loads project/city grants and employee vehicle assignments from trusted persisted relationships.
4. Rejects unknown, ambiguous, or unsupported role combinations.
5. Never accepts role or scope IDs from browser parameters.

Do not add guessed grant tables or broaden access to make a test pass. The data model and grant-management owner must be approved first.

## Open decisions before implementation

1. Confirm the canonical role mapping for all existing role atoms, including `fleet_manager`, `maintenance_manager`, `finance`, `viewer`, and `technician`.
2. Identify the authoritative source for project and city grants for each maintenance/finance user.
3. Identify the authoritative employee-to-vehicle assignment relationship and whether historical assignments grant access.
4. Confirm SharePoint internal field names and types against the actual provisioned Vehicles list.
5. Confirm whether VehicleId is the existing PostgreSQL UUID or a separate immutable fleet identifier.

## Acceptance tests to add before enabling the adapter

- Unknown role is denied.
- Missing actor is denied.
- Employee can read only vehicles assigned through trusted server-side assignment.
- Maintenance/finance actor can read only records matching all applicable trusted scope dimensions.
- Missing record scope is denied.
- Browser-supplied project/city/vehicle IDs cannot widen access.
- SharePoint list read failures do not silently fall back to PostgreSQL in production.
- Read-only stage issues no create/update/delete Graph requests.


## Approved access-management decision

The product owner approved the following operating rule: a Company Admin manages each user's authorized project and city scope from inside the application. These grants are maintained as trusted server-side data and are never supplied by the browser.

The intended administration workflow is:
1. Company Admin opens a user account.
2. Admin selects the projects and/or cities that the user is allowed to access.
3. The application persists the grants against that user and organization.
4. The server-side actor resolver loads those grants for every protected SharePoint operation.
5. Removing a grant takes effect on the next authorization check.

Employee users remain restricted to vehicles assigned to them through the existing VehicleAssignment relationship. Project/city grants do not automatically grant employee access to every vehicle in that scope.

## Implementation prerequisites discovered during repository review

- The current User resource stores roles as an array (`roles`), while AccessPolicy currently accepts one canonical `role`. A deterministic multi-role resolution rule is required; it must not be guessed.
- The existing UserProfile has a free-text city field. It is profile information only and must not be treated as an authorization grant.
- VehicleAssignment links a user (assignee) to a vehicle and has start/end datetimes. The current resource exposes a singular `has_one` assignment from Vehicle; whether historical or only current assignments grant access must be explicit.
- The reviewed application source does not currently expose dedicated Project or City resources in the vehicle-management domain. The source of valid project/city choices must therefore be established before building the admin grant selector.
- The current vehicle read policy in Ash authorizes reads broadly. The SharePoint integration must enforce its own server-side scope checks and must not assume that the existing Ash vehicle policy provides equivalent row-level security.

No database schema, UI, or runtime authorization behavior is changed by recording this decision.
