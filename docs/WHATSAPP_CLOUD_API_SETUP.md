# WhatsApp Business Platform Cloud API

## Scope of this integration stage

The application now has a server-side foundation for sending **approved WhatsApp message templates** through Meta's official Cloud API.

This stage does not:
- send messages automatically from unrelated fleet events such as breakdowns or repair updates;
- send free-form text messages;
- create or approve Meta message templates;
- send real messages until the company configures Meta credentials and explicitly enables the workflow.

All recipient resolution and authorization happen in trusted server-side code. The expiry workflow uses the active vehicle assignment and the assigned driver profile; the client itself does not select recipients.

## Server environment

Configure these variables in the deployment platform's secret manager or protected server environment:

- `WHATSAPP_CLOUD_API_ACCESS_TOKEN` — permanent/system-user access token with the required WhatsApp permissions.
- `WHATSAPP_PHONE_NUMBER_ID` — the WhatsApp Business phone-number ID from the Meta app.
- `WHATSAPP_GRAPH_API_VERSION` — an explicitly selected supported Graph API version, for example `v23.0`.

If all three variables are absent, WhatsApp remains disabled and the application can start normally. If only some are configured, startup configuration validation fails and lists the missing variable names without printing secret values.

Never place the access token in browser code, mobile app configuration, source control, logs, or chat messages.

## Meta prerequisites

1. The company owns or has authorized access to a Meta Business Portfolio.
2. A Meta app is configured with the WhatsApp product and the company's WhatsApp Business Account.
3. A phone number is registered for the Cloud API.
4. A system-user token is generated with the minimum required permissions.
5. Message templates are created in WhatsApp Manager and approved by Meta.
6. The selected Graph API version is supported by Meta at deployment time.

## Sending contract

Use `Fleetms.Integrations.WhatsApp.Client.send_template/6` from trusted server-side code only.

The client:
- accepts E.164 recipient numbers and normalizes common Saudi mobile formats;
- sends template messages only;
- validates template names, language codes, and component structure;
- disables automatic HTTP retries to reduce accidental duplicate sends;
- returns the provider message ID on success;
- does not expose the access token in returned errors.

Breakdown, repair-status, and invoice notifications are not connected. The scheduled vehicle-document expiry workflow is described below and remains opt-in until the company confirms the approved template and enables it.


## Vehicle document expiry reminders

The first fleet notification workflow scans active vehicle assignments every day at **08:00 Saudi time (Asia/Riyadh)**. It checks these vehicle fields:

- `registration_expiry_date`
- `insurance_expiry_date`
- `periodic_inspection_expiry_date`

A reminder job is created on the 30-day and 15-day milestones and is addressed to the currently assigned driver's profile phone number. Saudi mobile numbers in `05xxxxxxxx` format are normalized to E.164; other numbers must already be valid E.164 values.

The approved WhatsApp template must have five body placeholders in this exact order:

1. Vehicle name and license plate
2. Document type
3. Expiry date (ISO format, `YYYY-MM-DD`)
4. Days remaining (30 or 15)
5. Renewal instruction

Configure these additional server-side variables only after Meta has approved the matching template:

- `WHATSAPP_VEHICLE_EXPIRY_NOTIFICATIONS_ENABLED=true` — explicit opt-in; defaults to false.
- `WHATSAPP_VEHICLE_EXPIRY_TEMPLATE` — approved template name.
- `WHATSAPP_VEHICLE_EXPIRY_TEMPLATE_LANGUAGE` — template language code; defaults to `ar`.

The daily scan and sender workers remain inactive for WhatsApp delivery unless the opt-in flag is true and the Cloud API credentials are configured. The sender rechecks that the vehicle is still assigned to the same active driver and that the expiry date has not changed before sending.

The sender uses a unique Oban job for each tenant, assignment, vehicle, document, expiry date, and milestone to avoid repeat queueing. Automatic retries are intentionally disabled for the actual send job because a network timeout can leave the provider acceptance state uncertain; failed sends require operational review rather than risking a duplicate message.

The migration for the three expiry-date fields belongs to `priv/repo/tenant_migrations`, because vehicles are stored in each organization's tenant schema.
