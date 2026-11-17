# Saudi Sicli — SharePoint / Microsoft Graph Integration Contract

## Status and boundary
This is the implementation contract for the production data adapter. It does not claim that Microsoft Graph is connected or that SharePoint resources have been provisioned.

- Production system of record: SharePoint Lists.
- Binary files: SharePoint Document Library.
- Integration: Microsoft Graph v1.0 over HTTPS.
- Authentication: Microsoft Entra ID OAuth; use the authorization flow approved by company IT.
- Permissions: least privilege, approved by IT. Do not request tenant-wide permissions by default.
- PostgreSQL remains demo/development-only. Production must fail closed if SharePoint configuration is absent; never silently route production writes to PostgreSQL.
- Never commit tenant IDs, client IDs that are confidential, client secrets, certificates, access tokens, refresh tokens, or site/list identifiers tied to production.

## Configuration contract
Provide configuration through deployment secrets/environment variables only:

| Setting | Purpose |
|---|---|
| FLEET_DATA_ADAPTER | Explicit adapter selection: sharepoint or demo |
| MICROSOFT_TENANT_ID | Entra tenant identifier supplied by IT |
| MICROSOFT_CLIENT_ID | Entra application identifier supplied by IT |
| MICROSOFT_CLIENT_SECRET or certificate reference | Server-side credential, only if approved OAuth flow requires it |
| SHAREPOINT_SITE_ID | Provisioned SharePoint site identifier |
| SHAREPOINT_DRIVE_ID | Document library drive identifier |
| SHAREPOINT_LIST_*_ID | Provisioned list identifiers, one setting per list |

Do not add real values to tracked config files. Validate required settings at startup. If FLEET_DATA_ADAPTER=sharepoint and any required setting is missing, stop startup with a clear configuration error. Demo mode must be explicitly selected and visibly identified in the UI.

## Adapter boundary
Application/business logic must depend on a storage behaviour, not call Microsoft Graph directly from LiveViews.

Suggested operations:
- list(resource, filters, paging)
- get(resource, item_id)
- create(resource, attributes, actor)
- update(resource, item_id, attributes, actor, expected_version)
- deactivate(resource, item_id, actor)
- upload_document(parent_resource, parent_id, file, metadata, actor)
- download_document(document_id, actor)
- list_documents(parent_resource, parent_id, filters)

Every write must validate role and project/city scope server-side. Updates should use SharePoint ETags / If-Match where available to prevent lost updates. Use stable SharePoint item IDs as technical references and business codes as human-readable keys.

## Graph request conventions
- Use Microsoft Graph v1.0 endpoints under the provisioned site and list IDs.
- Read list items with the fields expansion and server-side paging; follow @odata.nextLink rather than assuming one page.
- Create/update list item fields through the list item fields endpoint.
- Use ETags for optimistic concurrency.
- Store files in the provisioned document library. Keep metadata linking each file to its parent record, document category, uploader, and upload timestamp.
- Do not expose Graph access tokens or raw Graph errors to end users. Log correlation/request IDs without logging credentials or sensitive file content.
- Retry only transient throttling/server failures with bounded exponential backoff and respect Retry-After. Do not retry validation or permission failures blindly.

## SharePoint list inventory
Provision list names and fields according to docs/SAUDI_SICLI_FLEET_MODULES.md, then add these operational lists:

### Fleet_BreakdownReports
- Title (Text): generated report number / display title
- VehicleId, ProjectId, CityId, DriverId (Text; indexed references)
- ReportedAt (DateTime), ReportedBy (Text)
- Category (Choice), Priority (Choice), Description (Multiple lines)
- Status (Choice): New, Reviewed, Sent to Workshop, Under Repair, Waiting for Parts, Waiting for Insurance Approval, Ready for Collection, Closed, Cancelled
- WorkshopId (Text), RequiresTowing (Yes/No)
- PickupLocation, DeliveryLocation (Multiple lines)
- TowingProvider, TowingMobile (Text)
- TowingCost (Currency), TowingInvoiceDocumentId (Text)
- CreatedAt, UpdatedAt (DateTime)

### Fleet_WorkOrders
- Title (Text): generated work-order number
- BreakdownReportId, VehicleId, WorkshopId, ProjectId (Text; indexed references)
- SentAt, ReceivedAt (DateTime)
- RequestedWork, CompletedWork (Multiple lines)
- PartsCost, LaborCost, OtherCost, VATAmount, TotalCost (Currency)
- ApprovedRepairCost, ActualRepairCost, AdditionalCost (Currency)
- AdditionalCostReason, DamagedPartDescription (Multiple lines)
- AdditionalPartCost, AdditionalLaborCost (Currency)
- RepairApprovalStatus, AdditionalApprovalStatus (Choice)
- RepairApprovedBy, AdditionalApprovedBy (Text)
- RepairApprovedAt, AdditionalApprovedAt (DateTime)
- Status (Choice), CreatedAt, UpdatedAt (DateTime)

### Fleet_Invoices
- Title (Text): invoice number
- InvoiceType (Choice): Repair, Spare Parts, Towing, Periodic Inspection, Tires, Other
- InvoiceDate (Date), VehicleId, WorkOrderId, BreakdownReportId, ProjectId, SupplierId (Text; indexed references)
- Amount, VATAmount, TotalAmount, PaidAmount, RemainingAmount (Currency)
- ApprovalStatus (Choice): Received, Under Review, Approved, Sent to Finance, Rejected
- ReviewedBy, ReviewedByRole, RejectedBy, RejectedByRole, ApprovedBy, ApprovedByRole, SentToFinanceBy, SentToFinanceByRole (Text)
- ReviewedAt, RejectedAt, ApprovedAt, SentToFinanceAt (DateTime)
- PaymentStatus (Choice): Unpaid, Paid
- PaymentReference, PaidBy, PaidByRole (Text)
- PaidAt (DateTime)
- DocumentId (Text), Notes (Multiple lines)
- CreatedAt, UpdatedAt (DateTime)

Saudi Sicli receives supplier invoices from workshops, maintenance centers, and
service providers; it does not issue customer invoices. Creating a Fleet_Invoices
item records a received supplier invoice and is not tax-invoice issuance.

The invoice workflow is:
1. Received: maintenance records the supplier invoice and attaches its PDF/image.
2. Under Review: maintenance checks it against the vehicle, breakdown report,
   work order, quotation, and approved repair scope.
3. Approved: a scoped Maintenance Manager approves the supplier invoice.
4. Sent to Finance: the Maintenance Manager explicitly hands the approved invoice
   to Finance. This transition is blocked until ApprovalStatus is Approved.
5. Paid: Finance records the full payment reference. PaymentStatus becomes Paid;
   ApprovalStatus remains Sent to Finance so Finance can retain its history.
6. Rejected: maintenance rejects an invoice that does not pass review.

Invoice creation must validate Amount + VATAmount = TotalAmount and initialize
PaidAmount to zero, RemainingAmount to TotalAmount, PaymentStatus to Unpaid, and
ApprovalStatus to Received. Approval and handoff metadata are server-managed.
Payment fields and approval/handoff fields cannot be changed through generic
invoice updates. The current payment workflow records one full payment only;
partial payments are not supported. Only a user assigned the Finance role may
read invoices that have been sent to Finance and record their payment. Finance
access is restricted to the user's assigned project/city scope and does not grant
access to other fleet resources or approval operations. Company Admin cannot
record invoice payments. The payment operation must use the SharePoint item ETag
to prevent concurrent duplicate updates and store the payment reference, actor
identity/role, and timestamp.

### Fleet_ApprovalRecords
- Title (Text): generated approval reference
- ApprovalType (Choice): Repair, Additional Repair Cost, Towing Invoice
- ParentRecordId (Text; indexed)
- Decision (Choice): Approved, Rejected
- ApprovedAmount (Currency)
- DecisionBy, DecisionByRole (Text)
- DecisionAt (DateTime)
- Comments (Multiple lines)

Only Maintenance Manager and authorized Maintenance Team members may approve repairs, additional repair costs, and towing invoices, within their assigned project/city scope. Company Admin may administer access. Do not introduce a Finance approval stage for repair authorization.

### Fleet_VehicleHistory
- Title (Text): event label
- VehicleId (Text; indexed), EventType (Choice), EventDate (DateTime)
- RelatedRecordId (Text), ProjectId, CityId (Text; indexed references)
- Summary (Multiple lines), Cost (Currency)
- ActorName, ActorEmail (Text)

### Fleet_AuditLog
- Title (Text): event summary
- EntityType, EntityId, Action (Text; indexed where useful)
- ActorId, ActorName, ActorEmail (Text)
- OccurredAt (DateTime; indexed)
- OldValues, NewValues (Multiple lines; JSON text)
- CorrelationId (Text)
- Application users must not be able to edit or delete audit entries. Enforce retention and restrictive permissions in SharePoint administration as well.

## Approval invariants
1. Repair work cannot be marked authorized until a Maintenance Manager or authorized Maintenance Team member approves it.
2. Towing invoices are approved by Maintenance Manager or authorized Maintenance Team member.
3. Additional damage/cost discovered after dismantling requires a separate additional-cost approval before the extra work proceeds.
4. An invoice for repair must not pass the application's approval gate when ActualRepairCost exceeds ApprovedRepairCost unless the additional amount has an approved record.
5. Record decision, approver, role, timestamp, approved amount, and comments.
6. Keep towing costs separate from repair costs.
7. Only a scoped Maintenance Manager may approve a received supplier invoice and send an approved invoice to Finance. Finance may only read invoices sent to Finance and record full payment within assigned project/city scope. Finance cannot approve repairs or edit fleet records; Company Admin cannot record payments.
8. Do not implement partial-payment workflows unless separately requested. The current implementation records full payment only.

## File metadata
For each document store: DocumentId, DriveItemId, ParentResource, ParentRecordId, DocumentCategory, FileName, ContentType, Size, UploadedBy, UploadedAt. Document categories include quotation, repair_invoice, towing_invoice, before_photo, after_photo, additional_damage_photo, inspection_report, receipt, and other.

## Provisioning checklist for IT
- Create the SharePoint site and dedicated document library.
- Create lists using the names and fields above; enable indexes for reference/status/date fields used by filters.
- Decide whether app-only or delegated OAuth is approved and provide the exact permission grant.
- Provide tenant/site/list/drive identifiers through a secure channel.
- Configure retention/versioning and restrict audit-list deletion.
- Provide a non-production test site and test identities before production onboarding.

## Acceptance criteria
- Production mode cannot silently use PostgreSQL.
- No secrets are stored in Git.
- All access checks happen server-side and include project/city scope.
- SharePoint paging, ETags, throttling, and error handling are implemented.
- File content is stored in the document library, not list text fields.
- Repair/towing approvals follow the stated roles and are auditable.
- No engine-number field is introduced.
- Existing records are never bulk-overwritten or deleted by setup/import operations.
