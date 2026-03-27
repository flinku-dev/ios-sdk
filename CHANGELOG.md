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
