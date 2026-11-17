# Developer Implementation Plan — Saudi Sicli Fleet Management

> Owner-approved implementation brief. Work on `feature/ui-dashboard-redesign` only.
> Do not modify or merge into `main`. Do not deploy or merge without separate explicit owner approval.

## Delivery rules
- Inspect the current implementation before changing it; preserve existing working features, data, and integrations.
- Make small, reviewable commits on this development branch. Keep CI green.
- Enforce permissions server-side/API-side; hiding UI controls is not authorization.
- Do not delete or replace existing functionality or data without documenting the impact and obtaining owner approval.
- Report progress at the end of every phase: changed files, delivered behavior, tests and results, CI run, risks/blockers, and remaining work.
- If a requirement conflicts with existing architecture or data, stop that specific change and explain the options rather than guessing.

## Phase 1 — Roles, permissions, and security (start immediately)
1. Define one canonical role model for Employee/Driver, Technician/Maintenance Team, Maintenance Manager, Fleet Manager, and Company Admin.
2. Reconcile legacy role names across Ash policies, user records, and SharePoint access policy (for example `admin` vs `company_admin`, `technician` vs `maintenance_team`). Provide backward-compatible mapping/migration; do not silently strand existing users.
3. Produce a role/action permission matrix covering read, create, update, assign, resolve, close, reopen, delete, approve, manage users/settings, and export.
4. Review all broad `authorize_if always()` rules and action-type bypasses on business resources. Retain only where demonstrably required and safe; add explicit authorization for sensitive operations.
5. Verify tenant isolation, record ownership, project/city/vehicle scope, and assignment rules using trusted server-side context.
6. Add positive and negative tests for every role and sensitive action, especially Issues/Breakdown Reports, Work Orders, users, SharePoint operations, and cross-tenant/cross-project access.
7. Document the final matrix and any compatibility decisions.

**Phase 1 acceptance:** no unauthorized role can read or mutate protected records or execute privileged actions; tests prove both allowed and denied cases; CI passes.

## Phase 2 — Complete the maintenance lifecycle
Complete and verify: breakdown report → review/triage → work order creation → assignment → workshop/repair → parts and labor → photos/documents and evidence → completion/collection → closure.
- Preserve links to vehicle, driver, project, workshop, and originating issue.
- Maintain status history and vehicle maintenance history.
- Validate required fields and prevent invalid state transitions.
- Preserve existing reminder/service-task behavior.

**Acceptance:** end-to-end tests cover normal, rejected, reopened, and waiting-for-parts/approval paths.

## Phase 3 — Invoices and Finance approvals
1. Inspect the current invoice source of truth and existing SharePoint integration before adding models or lists; avoid duplicate stores.
2. Complete invoice capture and validation for supplier/workshop, invoice number/date, vehicle, project, work order, parts, labor, tax, total, and supporting attachments as applicable.
3. Link each invoice to its vehicle, project, and maintenance/work order.
4. Require Maintenance Manager review/approval before Finance submission.
5. Block unapproved invoices from the Finance stage.
6. Audit approver, decision, timestamp, comments, changes, and handoff to Finance.
7. Apply role/tenant scope to invoice views, attachments, and exports.

**Acceptance:** tests prove an unapproved invoice cannot reach Finance, approved invoices retain traceable links and audit history, and existing Finance/SharePoint flows remain intact.

## Phase 4 — Dashboard
Improve role-aware KPIs and actionable lists for vehicles, open breakdowns, work orders by status, vehicles under repair, pending maintenance/finance approvals, upcoming registration/insurance/inspection expiries, and maintenance costs.
- Use accurate tenant-scoped queries and meaningful filters.
- Link each KPI/list item to its underlying record.
- Avoid displaying data outside the current user's authorization scope.

**Acceptance:** dashboard totals reconcile with source records and role-based visibility is tested.

## Phase 5 — Notifications and reports
- Implement reliable 30-day and 15-day reminders for vehicle registration (Istimara), insurance, and periodic inspection.
- Include vehicle, plate, project, expiry date, and responsible contact where permitted.
- Prevent duplicate notifications; define retry/error handling and notification audit history.
- Complete Excel/PDF reports with filters and permission-aware exports.
- Do not expose personal or fleet data to unauthorized recipients.

**Acceptance:** date-boundary, duplicate-prevention, delivery-failure, permissions, and export tests pass.

## Phase 6 — Final QA and release readiness
Run formatter, compile/build, all automated tests, authorization and tenant-isolation tests, integration checks, and relevant UI/manual scenarios.
- Fix failures and report exact test counts/results.
- Provide CI links and reproducible evidence for key workflows.
- Document known limitations, deployment/configuration requirements, and rollback considerations.
- Prepare a release checklist only. Do not merge, deploy, or alter `main` without separate explicit owner approval.

## Required first response from developer
Begin with Phase 1 on this branch. Confirm the branch and baseline CI status, list the exact files/modules to be changed, identify any schema or integration risks, then implement Phase 1 in small commits. Do not stop after producing another proposal unless blocked by a concrete issue requiring owner input.
