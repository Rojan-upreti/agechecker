# Production scan-usage API contract

The iOS guest counter is a local UX control and is not authoritative. Production enforcement requires a server-controlled UTC allowance.

## Start or check an allowance

`POST /usage/scan-attempts`

Request:

```json
{
  "installation_id": "opaque-installation-identifier",
  "workflow_id": "uuid",
  "tier": "base"
}
```

The server derives the authenticated account from the Cognito access token when present. It must not trust a client-supplied account, organization, UTC date, count, or entitlement.

Response:

```json
{
  "attempt_id": "server-id",
  "allowed": true,
  "remaining": 4,
  "resets_at": "2026-11-10T00:00:00Z",
  "expires_at": "2026-11-09T23:59:59Z"
}
```

Use an atomic conditional write so concurrent requests cannot reserve more than the allowance. Apply rate limits by account and privacy-preserving installation identifier.

## Complete a successful scan

`POST /usage/scan-attempts/{attempt_id}/complete`

Request:

```json
{
  "idempotency_key": "workflow-uuid"
}
```

Completion must be idempotent. Only a successfully completed logical document workflow consumes the reservation. Camera frames, front/back steps, retries, failures, and cancellations do not create additional usage.

## Cancel or expire an attempt

`DELETE /usage/scan-attempts/{attempt_id}`

Uncompleted reservations must expire automatically after a short server-controlled interval. Define the offline policy explicitly; fail closed after the locally cached allowance is exhausted.

## Premium entitlement

`GET /account/feature-access`

Return server-verified organization membership, permissions, and Premium entitlement. A Cognito login or client-side StoreKit Boolean must never authorize Rekognition or another billable biometric operation. Keep `POST /verification/session` disabled until this authorization layer is deployed and audited.
