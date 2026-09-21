# theme.watch — Hardening and Gaps Spec

**Written**: 2026-09-21. **Owner**: Taylor. **Audience**: an agent picking this up cold.
**Status of the product model**: unchanged. theme.watch remains a paid app-developer platform for compatibility tracking, version alerts, and public app profiles. Do not redesign the product. This doc is engineering only.

Read [CLAUDE.md](../CLAUDE.md) first (non-negotiables, stack, key paths). Then [NEXT-STEPS.md](../NEXT-STEPS.md) for the May 2026 handoff and the browser test plan. The API contract at `~/RubyOnRails/web_scraper/docs/api/theme-watch-contract.md` is authoritative for anything that touches shopinfo.app.

## Working rules for the agent

- Never run git commands. Taylor commits and pushes. Report what changed and stop.
- Never start or stop the dev server. Ask if a server action is needed.
- Never invent an API endpoint. If one is missing, update the contract doc in the web_scraper repo first, then build it there, then consume it here.
- Work one workstream at a time in the order below. Each has a "done when". Update the checkbox list at the bottom as you go.
- The theme-watch-app repo has no database. Do not add one. Do not add Active Record.

## Snapshot of the codebase (2026-09-21)

Roughly 30 source files. Rails 7.1.6, Ruby 3.2.2, Puma 8, Faraday 2.14, jwt 2.10. Node 25.2.1 in the Docker build. Tailwind v4, esbuild, Stimulus, Turbo. Deployed on Render as a Docker web service with one Puma worker and five threads.

What works in production: Clerk sign-in, dashboard, My Apps list, and a compatibilities manage page (list, add row, edit row) that has never been exercised against real data because no listing has ever been claimed. The claim flow does not exist yet on either side.

What does not exist: tests, CI, timeouts on outbound HTTP, a content security policy, host authorization, any way for a developer to claim or edit a listing, or to delete a compatibility row.

---

## Workstream 1 — Runtime upgrade

**Why first**: Ruby 3.2 left security support in March 2026. Rails 7.1 loses security fixes on 2026-10-01. Node 25 is a non-LTS odd release. The codebase is small enough that this is an afternoon and it should land before any feature work builds on the old stack.

Tasks:

1. Ruby to the latest 3.4.x. Update `.ruby-version`, `Gemfile`, and `ARG RUBY_VERSION` in `Dockerfile`.
2. Rails to the latest stable 8.x. Bump `Gemfile`, `bundle update rails`, then run the updater. It is interactive and prompts per file, which does not work from an agent shell, so run `bin/rails app:update --force` on a clean working tree and then review the full diff file by file. It overwrites generated config, so restore these by hand after it runs:
   - `config/application.rb`: keep the selective railtie requires (no `rails/all`, no Active Record, no Active Storage). Drop the Action Cable require per Workstream 7. Keep `config.autoload_lib`. Set `config.load_defaults` to the new version.
   - `config/environments/production.rb`: keep `force_ssl`, the STDOUT logger, `log_tags`, and the `RAILS_LOG_LEVEL` env read.
   - `config/puma.rb`: keep the `WEB_CONCURRENCY` branch that calls `preload_app!` when there is one worker, and `port ENV.fetch("PORT") { 3001 }`.
   - `bin/docker-entrypoint`: must stay the two-line `exec` version. The generated one runs `db:prepare`, which will fail.
   - Do not accept any new `database.yml`, `storage.yml`, `queue.yml`, `cache.yml`, or `recurring.yml`. Delete them if generated. Solid Cache, Solid Queue, and Solid Cable must not be added. Keep the cookie session store.
   - Review every new initializer it drops in. Most will be `new_framework_defaults_8_x.rb`, which should be deleted once `load_defaults` is bumped.
   Boot the app after the review, not before.
3. Node to 24 LTS in `Dockerfile`. Remove `python-is-python3` and `node-gyp` from the build stage, neither is needed by esbuild or Tailwind.
4. Bump `esbuild`, `@hotwired/*`, `tailwindcss`, `@tailwindcss/cli` to current. Rebuild assets and confirm the landing page and authenticated layout look identical.
5. Bump `jwt`, `faraday`, `puma` to current within their major versions.

Done when: `bin/rails runner 'puts Rails.version'` prints 8.x, `docker build .` succeeds, the app boots locally with the `.env` values, and the sign-in page renders the Clerk component.

**Stop here.** Report the diff to Taylor and end the session. Taylor commits the upgrade on its own before any other workstream starts, so it can be reverted or bisected independently of feature work. Do not begin Workstream 2 in the same session.

---

## Workstream 2 — Outbound HTTP hardening

**Why**: `app/services/shopinfo_api.rb` builds its Faraday connection with no timeouts. `ClerkAuthenticatable#fetch_clerk_jwks` uses bare `Net::HTTP` with 60-second defaults. Puma has five threads. A slow shopinfo.app deploy stalls every theme.watch request for up to a minute per thread.

Tasks:

1. In `ShopinfoApi#connection`, set `f.options.open_timeout = 3` and `f.options.timeout = 5`. Add the `faraday-retry` gem and retry idempotent GETs only (max 2, with backoff). Never retry PUT, POST, PATCH, or DELETE.
2. Rescue `Faraday::TimeoutError` alongside `Faraday::ConnectionFailed` everywhere the client is called (see Workstream 3 for where that rescue should live).
3. In `fetch_clerk_jwks`, replace `Net::HTTP.get_response` with an explicit `Net::HTTP.start` block setting `open_timeout = 3` and `read_timeout = 3`. If the fetch fails and there is a cached JWKS, log a warning and keep serving from cache rather than raising.
4. Add a `User-Agent` header on the Faraday connection identifying theme.watch, so shopinfo.app logs can tell the two apps apart.

Done when: a unit test with a stubbed slow endpoint proves the client raises within the configured timeout, and a JWKS fetch failure with a warm cache does not sign the user out.

---

## Workstream 3 — Error handling consolidation

**Why**: `DashboardController`, `MyAppsController`, and `MyAppCompatibilitiesController` each carry a copy-pasted block of four rescue clauses. The rescue strings are developer debugging copy ("Confirm the same Clerk instance backs both apps", "Is the web_scraper dev server running?") and they render to end users.

Tasks:

1. Add `rescue_from` handlers in `ApplicationController` for `ShopinfoApi::Unauthorized`, `ShopinfoApi::Forbidden`, `ShopinfoApi::Error`, `Faraday::ConnectionFailed`, and `Faraday::TimeoutError`. Delete the per-controller rescue blocks.
2. Each handler logs the full detail (status, body, base URL, request ID) at `error` level and sets a single user-facing message. User copy must be plain and non-technical, for example "shopinfo.app is not responding right now. Try again in a minute." The debugging hints move into the log line, not the page.
3. Render errors through one shared partial `app/views/shared/_api_error.html.erb`. Replace the three inline amber panels with it.
4. Move flash rendering into `app/views/layouts/authenticated.html.erb` so every authenticated page shows notices and alerts. Remove the flash markup from the compatibilities view.
5. `SessionsController` re-includes `ClerkAuthenticatable`, which `ApplicationController` already includes. Remove the duplicate.
6. The `DELETE /sign-out` route and `SessionsController#destroy` are unused. Sign-out is handled by the Stimulus controller calling Clerk. Either wire the sidebar button to a real form that hits the route and then calls Clerk, or delete the route and action. Prefer delete.

Done when: no controller has a `rescue` block for API errors, grepping the app for "web_scraper" returns nothing outside comments, and a forced 503 from a stubbed API shows the friendly message with the detail in the log.

---

## Workstream 4 — Tests and CI

**Why**: the test directory is untouched Rails scaffolding. The two components that have already broken twice in production (JWT verification and the API client) have zero coverage. There is no `.github` directory.

Use Minitest, which is already wired. Add `webmock` to the test group.

Tasks:

1. `test/services/shopinfo_api_test.rb` using `Faraday::Adapter::Test` stubs. Cover: 200 returns parsed body, 401 raises `Unauthorized`, 403 raises `Forbidden` with `.reason`, 422 raises `Error` with status, timeout raises `Faraday::TimeoutError`, base URL trailing-slash normalization, and that `update_app_compatibility` URL-encodes the theme title.
2. `test/controllers/concerns/clerk_authenticatable_test.rb`. Generate an RSA keypair in the test, stub the JWKS URL with WebMock to return the public key as a JWK, and sign tokens with the private key. Cover: valid token sets `clerk_user_id`, expired token is rejected, wrong issuer is rejected, wrong key is rejected, missing token redirects to sign-in, bearer header takes precedence over cookie, JWKS is cached between requests.
3. Integration tests for the three authenticated controllers. Stub the API client at the `ShopinfoApi` boundary. Cover the happy path, the empty state, and one API failure each. For compatibilities, cover create with a blank theme title, create success, update success, and the `admin_locked` forbidden branch showing the correct flash.
4. A `test/controllers/pages_controller_test.rb` asserting the landing page renders and contains no `href="#"` links (the CLAUDE.md rule). In-page anchors like `#features` are fine, bare `#` is not.
5. Add `.github/workflows/ci.yml`: checkout, setup Ruby from `.ruby-version`, setup Node 24, `bundle install`, `yarn install --frozen-lockfile`, `yarn build && yarn build:css`, `bin/rails test`. Run on push and pull request.

Done when: `bin/rails test` is green locally and the workflow file passes on the first push.

---

## Workstream 5 — Auth flow correctness

Tasks:

1. `ClerkAuthenticatable#require_clerk_user!` stores `session[:post_sign_in_redirect]` but nothing reads it. `app/views/sessions/new.html.erb` hardcodes `/dashboard` as the after-sign-in URL. Fix: `SessionsController#new` reads and deletes the session key, validates it is a relative path starting with `/` and not `//`, falls back to `dashboard_path`, and passes it to the Clerk mount data attribute. Same for sign-up.
2. Add a `return_to` guard test to Workstream 4's concern tests: a stored value of `https://evil.example` or `//evil.example` must fall back to the dashboard.
3. Sidebar identity: when the Clerk session token has no `email` claim (the current state until Taylor customizes the token in the Clerk dashboard), the sidebar shows the raw Clerk user ID. Show "Signed in" as the label instead of the ID, and keep the ID only in the `title` attribute.

Done when: signing in from a direct hit on `/my-apps/foo/compatibilities` lands back on that page, and a poisoned session value does not open-redirect.

---

## Workstream 6 — Security headers and config

Tasks:

1. `config/initializers/content_security_policy.rb`: enable a policy. Third parties are exactly: the Clerk Frontend API host (script, connect, frame, img), `cdn.usefathom.com` (script), `fonts.googleapis.com` (style), `fonts.gstatic.com` (font), `shopinfo.app` (img for listing icons), and the waitlist Worker host (connect). The landing page has an inline JSON-LD `<script>`, so either use a nonce or move JSON-LD to a `content_for` block with a nonce helper. Ship as `report_only` for one deploy, then enforce.
2. `config/environments/production.rb`: set `config.hosts` to `theme.watch`, `www.theme.watch`, and the `onrender.com` hostname. Exclude `/up` from host authorization so the Render health check keeps working.
3. Confirm `config.force_ssl = true` still plays with Render's proxy after the Rails upgrade (Rails 8 changed `assume_ssl` defaults). Set `config.assume_ssl = true` explicitly.
4. Cookie session: set `config.session_store :cookie_store, key: "_theme_watch_session", same_site: :lax, secure: Rails.env.production?` explicitly in an initializer so the settings are visible rather than inherited.

Done when: the Render deploy serves the CSP header, the browser console shows no CSP violations on landing, sign-in, dashboard, My Apps, and compatibilities pages, and a request with `Host: example.com` returns 403.

---

## Workstream 7 — Remove unused machinery

Tasks:

1. Remove `action_cable/engine` from `config/application.rb`, delete `app/channels/`, `config/cable.yml`, and `test/channels/`.
2. Remove `jbuilder` from the Gemfile. No view renders JSON.
3. Delete `app/javascript/controllers/hello_controller.js` if it is the Rails default and unused.
4. Delete `app/views/layouts/mailer.*` and `app/mailers/` only if Action Mailer is also removed. Keep Action Mailer if Phase 3 alerts might send from this app. Decision: keep mailer, remove the rest.

Done when: the app boots, `bin/rails test` is green, and `bundle exec rails routes` shows no cable mount.

---

## Workstream 8 — View cleanup

Tasks:

1. Extract the compatibility status options (`supported`, `needs_customization`, `not_supported`, `unknown`) into a constant on a small `Compatibility` plain Ruby object or a helper, and use it in both selects in `app/views/my_app_compatibilities/index.html.erb`. The labels appear twice today.
2. Render `updated_at` on compatibility rows as relative time via `time_ago_in_words` with the ISO timestamp in a `<time datetime>` attribute, instead of the raw string.
3. The landing page mock at `app/views/pages/landing.html.erb` around line 335 says "See all 12 compatible apps." Replace the number with a neutral label such as "See all compatible apps." CLAUDE.md forbids fabricated counts even in illustrations.
4. Use Rails `button_to` or a real form for any action that currently relies on JavaScript alone. Check that every interactive element has a visible focus state (the `focus:border-tw-400` pattern is fine, but buttons have none). Add `focus-visible:ring-2 focus-visible:ring-tw-400` to the shared button classes.
5. The `alerts` and `settings` pages are placeholders. Leave them, but add a one-line "Coming in Phase 3" note so a real user does not think the page is broken.

Done when: the compatibilities page has one source of truth for status options, keyboard tabbing through the sidebar and forms shows a visible ring on every stop.

---

## Workstream 9 — Feature gaps (cross-repo)

These need endpoints on shopinfo.app. The API side lives in `~/RubyOnRails/web_scraper/`. Pattern to copy on that side: `app/controllers/api/v1/compatibilities_controller.rb` (hybrid auth, ownership check, override-authority guard) and its spec at `spec/requests/api/v1/compatibilities_spec.rb`. On the theme.watch side, copy the shape of `MyAppCompatibilitiesController`.

Order matters. The claim flow goes first because it is the only thing that lets Taylor test the rest without a Rails console.

### 9a. Claim flow — `POST /api/v1/apps`

Contract section already written. Behavior: find `AppListing` by `shopify_app_store_url`. Unclaimed → claim, attach optional fields, open the 14-day review window, 200. Claimed by someone else → 409 with `reason: "app_already_claimed"`. Not found → create with slug derived from the App Store URL path, claim, open window, 201. Already claimed by the caller → 200 idempotent.

Slug derivation: take the last path segment of the URL, downcase, strip anything not `[a-z0-9-]`. Reject the request with 422 if the URL host is not `apps.shopify.com`.

theme.watch side: `ShopinfoApi#claim_app(attrs)` calling a new private `post`. A `ClaimsController` with `new` and `create`. A "Claim an app" page at `/my-apps/claim` with a single required field for the App Store URL and optional name, category, support URL, docs URL. Link to it from the My Apps empty state and from a button in the My Apps header. On 409, show the reason in the flash. On success, redirect to My Apps with a notice.

Done when: the web_scraper spec covers all four branches plus the bad-host 422, Taylor can claim a real listing from the browser, and the compatibilities test plan in NEXT-STEPS.md can be run end to end.

### 9b. Delete a compatibility row — `DELETE /api/v1/apps/:slug/compatibilities/:theme_title`

Same ownership and override-authority rules as PUT. 204 on success, 404 if the row does not exist, 403 `not_owner` or `admin_locked` as with PUT.

theme.watch side: `ShopinfoApi#delete_app_compatibility(slug, theme_title)`, a `destroy` action and route, and a delete button per row using `button_to` with `method: :delete` and a `data-turbo-confirm`. Keep the confirm as a Turbo confirm, not a JavaScript `confirm()` call in custom code.

### 9c. Edit a listing — `PATCH /api/v1/apps/:slug`

Editable fields per contract: `name`, `description`, `category`, `icon_url`, `support_url`, `docs_url`, `visible_publicly`. Ownership check only, no override-authority guard. Extract the `caller_is_owner?` helper from `CompatibilitiesController` into a shared concern on the web_scraper side since this is the third controller to need it.

theme.watch side: `ShopinfoApi#update_app(slug, attrs)`, an `edit` and `update` on a `MyAppsController` (or a new `MyAppListingsController`), and an "Edit listing" link on each My Apps card. The category select must come from `GET /api/v1/apps/categories`, not a hardcoded list.

### 9d. Contract doc

After each endpoint ships, mark it `(live)` in `theme-watch-contract.md` and note the date. The contract's top-level status line still says "Design — endpoints not yet implemented" and is wrong. Fix it in the same pass.

---

## Workstream 10 — Ops items

Not code in this repo, but the agent should surface them to Taylor at the right moment.

- **Clerk session token claims** (Taylor, Clerk dashboard, 2 minutes): add `email` and `name` to the session token. JSON in NEXT-STEPS.md. Unblocks the dashboard greeting and sidebar identity.
- **Delete the old landing-page Cloudflare Worker**: the fallback period ended 2026-06-05. Safe to delete now. The waitlist Worker is a different Worker and stays.
- **Render internal hostname**: swap `SHOPINFO_API_BASE_URL` to the private-network hostname once confirmed both services are in the same Render workspace. Do this after Workstream 2 so the timeouts are in place.
- **Clerk production instance**: still deferred until real users. Needs matching `CLERK_FRONTEND_API` on both Render services at the same time.
- **Rate limiting on shopinfo.app Clerk endpoints**: still deferred. Do it after 9a through 9c exist.

---

## Verification checklist for the whole pass

1. `bin/rails test` green locally.
2. `docker build .` succeeds and the image boots with the production env vars.
3. Render deploy goes green on `/up`.
4. Browser: sign in, claim a listing, add a compatibility row, edit it, delete it, edit the listing, sign out. No console errors, no CSP violations.
5. Anonymous curl against `https://shopinfo.app/api/v1/apps/<slug>/compatibilities` shows only public rows.
6. NEXT-STEPS.md updated with the new state and date.

## Progress

- [x] 1 Runtime upgrade (2026-09-21, awaiting Taylor commit)
- [ ] 2 Outbound HTTP hardening
- [ ] 3 Error handling consolidation
- [ ] 4 Tests and CI
- [ ] 5 Auth flow correctness
- [ ] 6 Security headers and config
- [ ] 7 Remove unused machinery (task 1, Action Cable, already done in W1)
- [ ] 8 View cleanup
- [ ] 9a Claim flow
- [ ] 9b Delete compatibility row
- [ ] 9c Edit listing
- [ ] 9d Contract doc updated
- [ ] 10 Ops items surfaced

---

## Parked strategy notes (not for the agent, for Taylor)

Discussed 2026-09-21. Model stays as-is. Recorded so the conversation is not lost.

- Shopify shipped standard storefront events and actions on 2026-06-17. Script tags stop being creatable 2026-10-01 and stop rendering 2027-03-01. This standardizes the theme-to-app interface and shrinks the compatibility surface over time for apps on standard themes.
- Counterpoint that carried: custom and heavily modified themes on large merchants will not dispatch standard events for a long time, and those merchants are the high-value target. Even Plus stores Taylor works on have not moved. So the compatibility-tracking premise holds for the segment that matters.
- Idea to revisit once there is real data: shopinfo.app already scans storefronts. A per-theme "which standard events does this theme dispatch" scorecard would be auto-detected compatibility data with no cold-start problem. Could complement self-reported rows rather than replace them.
- Idea to revisit: paid placement on shopinfo.app theme pages as a second revenue line alongside the subscription. Depends on merchant traffic. Check Fathom for the last 90 days before deciding.
- Cost: theme.watch's Render service is about 7 of the roughly 50 dollars a month. Postgres is the largest line. Consolidating the portal into shopinfo.app as a namespace would remove the second service and the cross-service Clerk sync, but is not worth doing until the feature set stabilizes.
