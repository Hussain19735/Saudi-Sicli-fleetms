# WhatsApp Business Platform Cloud API

## Scope of this integration stage

The application now has a server-side foundation for sending **approved WhatsApp message templates** through Meta's official Cloud API.

This stage does not:
- send messages automatically from fleet events;
- select drivers or other recipients;
- send free-form text messages;
- create or approve Meta message templates;
- send real messages until the company configures Meta credentials and explicitly enables the workflow.

Callers must perform authorization and resolve the intended recipient on the server before calling the client.

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
- accepts E.164 recipient numbers;
- sends template messages only;
- validates template names, language codes, and component structure;
- disables automatic HTTP retries to reduce accidental duplicate sends;
- returns the provider message ID on success;
- does not expose the access token in returned errors.

No fleet event handler or scheduled worker is connected in this initial stage. Add those only after the company confirms the approved message templates, recipient rules, language policy, and triggering events.
