## 0.7.0 — 2026-07-21

* `Flinku.resetAll()` — testing-only full local wipe (match cache, user id, pending referral, tracked-once flags). Does not change `reset()` behaviour.
* Pending referral index entry is removed when a pending referral record expires by TTL.

## 0.6.0

* Pending referral attribution is stored separately from the match cache (`flinku_pending_referral_{projectId}`)
* `Flinku.reset()` no longer clears referral attribution
* Failed track POSTs leave the pending record in place and retry on the next `setUserId` or `configure` (when a userId is already stored)
* Pending referrals expire after 30 days

## 0.5.0

* Referral once-per-user flag is now `referral_tracked_{projectId}_{userId}`
* Persist and send `linkId` from the match response when tracking referrals
* README Referrals section documents `apiKey` on `configure`

## 0.4.0

* `Flinku.setUserId` — store app user id and auto-track referrals from cached match `referrerId`
* `Flinku.qualifyReferral` — mark a referred user as qualified for an optional event

## 0.3.3 - Support publishable API keys (flk_pk_). Debug-mode warning when a secret key is embedded. Surface Allowed Domains errors clearly.

## 0.3.2 - Add readClipboard option to configure(); clipboard read now happens after server match

## 0.3.1 - Add createLinkInstant for instant link creation without waiting for server

## 0.3.1

* Clipboard-based deferred deep linking fallback when fingerprint match fails
* Added `matchWithClipboardUrl(_:)` (`POST /api/match` with `clipboardUrl`)
* Added `matchType` to `FlinkuLink`

## 0.3.0

* Added `FlinkuLinkOptions` and `FlinkuCreatedLink` for programmatic link creation
* Added `createLink(_:completion:)` and `createLinks(_:completion:)` (batch `POST /api/links/batch`)
* Optional `apiKey` on `Flinku.configure` / `FlinkuConfig` with `Bearer` auth for create APIs
* Added `apiBaseUrl` on `FlinkuConfig` (apex host derived from project `baseUrl`, e.g. `https://myapp.flku.dev` → `https://flku.dev`)
* Added `FlinkuError` cases: `missingApiKey`, `invalidResponse`, `invalidURL`, `notConfigured`

## 0.2.0

* Project-based architecture — baseUrl is now your project subdomain URL
* Added params, title, clickedAt, subdomain, projectId to FlinkuLink
* Added timeout configuration (default 5 seconds)
* Added retry logic — retries once on network failure
* Added double-match prevention using UserDefaults
* Added Flinku.reset() for testing
* Subdomain auto-extracted from baseUrl

## 0.1.0

* Initial release
