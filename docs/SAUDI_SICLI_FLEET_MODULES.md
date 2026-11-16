# Saudi Sicli Fleet Modules — Implementation Contract

## Scope
This document defines the next implementation slice for Projects, Cities, Workshops, Drivers, and vehicle relationships. It is a build contract, not a claim that these modules are already implemented.

## Production storage boundary
- Production records belong in Microsoft 365 SharePoint Lists.
- Photos, quotations, invoices, inspection evidence, and other attachments belong in a SharePoint Document Library.
- Access is through Microsoft Graph using Entra ID OAuth and least-privilege permissions.
- PostgreSQL may remain a development/demo adapter only. It must not become the production system of record.
- No tenant URL, list IDs, app registration, client secret, or production credentials are assumed to exist yet.
- Until IT provisions the SharePoint site and app registration, do not write company data to a guessed tenant or silently treat local PostgreSQL as production.

## SharePoint list model

### Fleet_Cities
| Field | Type | Notes |
|---|---|---|
| Title | Text | City display name |
| CityCode | Text, indexed | Stable unique business code |
| Region | Text | Saudi administrative region |
| IsActive | Yes/No | Soft deactivation; preserve history |

### Fleet_Projects
| Field | Type | Notes |
|---|---|---|
| Title | Text | Project name |
| ProjectCode | Text, indexed | Stable unique project code |
| ClientName | Text | Customer/client |
| CityId | Text, indexed | Reference to Fleet_Cities item ID |
| ProjectManager | Text | Project manager name |
| StartDate | Date | Optional |
| EndDate | Date | Optional |
| Status | Choice | Planned, Active, On Hold, Completed, Cancelled |
| IsActive | Yes/No | Soft deactivation |

### Fleet_Workshops
| Field | Type | Notes |
|---|---|---|
| Title | Text | Workshop name |
| WorkshopCode | Text, indexed | Stable unique business code |
| WorkshopType | Choice | General, Mechanical, Electrical, Tires, Bodywork, Inspection, Other |
| CityId | Text, indexed | Reference to Fleet_Cities item ID |
| Address | Multiple lines | Physical address |
| ContactName | Text | Contact person |
| Mobile | Text | Contact mobile |
| Email | Text | Contact email |
| VATNumber | Text | Tax registration |
| CommercialRegistration | Text | CR number |
| ApprovalStatus | Choice | Pending, Approved, Suspended |
| PaymentTerms | Multiple lines | Agreed terms |
| WarrantyTerms | Multiple lines | Warranty terms |
| RelationshipStartDate | Date | Optional |
| IsActive | Yes/No | Soft deactivation |

### Fleet_Drivers
| Field | Type | Notes |
|---|---|---|
| Title | Text | Driver full name |
| EmployeeNumber | Text, indexed | Optional stable employee reference |
| Mobile | Text | Driver mobile |
| Email | Text | Optional |
| CityId | Text, indexed | Main city reference |
| ProjectId | Text, indexed | Current project reference |
| Status | Choice | Active, On Leave, Inactive |
| IsActive | Yes/No | Soft deactivation |

### Fleet_Vehicles relationship fields
Vehicle records should reference ProjectId, CityId, and PrimaryDriverId using SharePoint item IDs stored as text, with indexes on fields used in filters. Do not add an engine-number field. Preserve existing vehicle identifiers and records.

### Fleet_VehicleAssignments
Use a separate assignment list to preserve history and support drivers assigned to multiple vehicles:
- VehicleId, DriverId, ProjectId, CityId
- AssignmentStartDate, AssignmentEndDate
- IsPrimary, Status, Notes
- CreatedBy, CreatedAt
A current assignment has no AssignmentEndDate and Status = Active. Enforce one active primary driver per vehicle in application logic.

## Import workflow
1. Accept .xlsx and .csv only.
2. Read headers and allow column mapping independent of column order.
3. Preview rows before any write.
4. Validate required fields, dates, phone values, project/city references, and duplicate vehicle plates or business codes.
5. Show valid, duplicate, and invalid row counts with row-level reasons.
6. Import valid rows only after explicit user confirmation.
7. Never overwrite or delete an existing record during import by default.
8. Provide a downloadable error report and allow corrected rows to be re-imported.
9. Import cities and projects before vehicles; import drivers before vehicle assignments.

## Permissions
- Company Admin: all projects and cities.
- Maintenance Manager: all projects and cities.
- Maintenance Team: assigned projects and cities only.
- Employee: only their assigned vehicle and related breakdown status; no editing of vehicle master data or costs.
- Enforce permissions on the server/API, not only by hiding UI controls.

## Audit and data integrity
- Use immutable SharePoint item IDs as technical references; retain business codes as human-readable identifiers.
- Record who created or changed records and timestamps.
- Deactivate master data instead of deleting records referenced by vehicles, work orders, or history.
- Keep assignment history; do not overwrite historical driver/project relationships.
- Avoid SharePoint lookup-column assumptions that require relational SQL behavior. Use indexed text reference IDs and validate references in the application.

## Delivery sequence
1. Cities and Projects master data.
2. Workshops master data and approval status.
3. Drivers and historical vehicle assignments.
4. Vehicle forms and filters wired to these references.
5. Excel import preview, validation, duplicate detection, and controlled import.
6. Microsoft Graph adapter after IT supplies the SharePoint site and Entra app registration.

## Acceptance checks
- No engine-number field is introduced.
- No existing data is deleted or overwritten.
- Driver-to-vehicle history remains queryable after reassignment.
- Employees cannot edit master data or financial amounts.
- Production configuration cannot silently fall back to PostgreSQL.
- Import has a preview and explicit confirmation step.
