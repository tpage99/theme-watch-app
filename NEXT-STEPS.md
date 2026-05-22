# Where to pick up

Living handoff doc. Update as state changes. **Last updated: 2026-05-22 (end of session).**

For project context, conventions, and architectural decisions see [CLAUDE.md](CLAUDE.md). For the original 9-step bootstrap plan see `~/RubyOnRails/web_scraper/docs/theme-watch-app-bootstrap.md`. For the API contract see `~/RubyOnRails/web_scraper/docs/api/theme-watch-contract.md`.

---

## Current state

End-to-end working on production as of 2026-05-22:

- ✅ Rails 7.1 app scaffolded, deployed to Render at `https://theme.watch` (DNS cutover complete, SSL valid)
- ✅ Clerk auth wired via JWKS verification (no backend SDK — Clerk JS sets `__session` cookie client-side as a fallback even on production-style apex domains, so the handshake JWT in the URL is safely ignored). GitHub OAuth sign-in verified working on `https://theme.watch`.
- ✅ Faraday client (`ShopinfoApi`) talking to production `https://shopinfo.app/api/v1`. `me_ping` and `me_apps` both live.
- ✅ `/dashboard` renders Hello panel pulled from `/api/v1/me/ping`
- ✅ `/my-apps` renders empty-state placeholder pulled from `/api/v1/me/apps` (no claimed listings yet — admin would need to `assign_claim` one to your AppDeveloper for cards to appear)
- ✅ Waitlist form on landing page still POSTing successfully to the Cloudflare Worker post-cutover

---

## Pending commits / loose ends from this session

Things changed during this session — verify these are committed and pushed before you walk away:

**`~/RubyOnRails/web_scraper/` (already pushed by Taylor):**
- `app/controllers/api/v1/me_controller.rb` — added `apps` action + includes for `CursorPagination` and `AppListingSerialization`
- `app/controllers/api/v1/apps_controller.rb` — refactored to use the new shared serializer concern
- `app/controllers/concerns/api/v1/app_listing_serialization.rb` — NEW, shared serializer
- `config/routes.rb` — added `get "me/apps" => "me#apps"`
- `spec/requests/api/v1/me_spec.rb` — 6 new examples for `/me/apps`
- `docs/api/theme-watch-contract.md` — marked `/me/apps` as live

**`~/RubyOnRails/theme-watch-app/` (verify pushed):**
- `app/controllers/concerns/clerk_authenticatable.rb` — one-line fix: `session[:post_sign_in_redirect] = request.path` (was `request.fullpath`). Without this, Clerk's handshake redirect overflowed the 4KB session cookie and 500'd the dashboard.
- `app/services/shopinfo_api.rb` — added `me_apps` method
- `app/controllers/my_apps_controller.rb` — wired to `/me/apps` with rescue pattern mirroring DashboardController
- `app/views/my_apps/index.html.erb` — replaced placeholder with real listing cards + empty/error states
- `NEXT-STEPS.md` — this doc

**Render env vars set during this session (one-time):**
- `theme-watch` service: `SHOPINFO_API_BASE_URL=https://shopinfo.app/api/v1` (was missing → defaulted to localhost → connection-refused)
- `shopinfo-web` service: `CLERK_FRONTEND_API=<same value as theme-watch>` (was missing → `ENV.fetch` raised → 500 on every `/me/*` request)

**In-progress when session ended:**
- Customizing the Clerk session token to include `email` + `name` claims (Clerk dashboard → Sessions → Customize session token). Two-line JSON change:
  ```json
  {
    "email": "{{user.primary_email_address}}",
    "name": "{{user.full_name}}"
  }
  ```
  Once added + you sign out / back in, dashboard's "Hello, developer." becomes "Hello, taylor@…" and the "Email (from shopinfo.app)" dl field populates on next `/me/ping`. No code change needed; both apps already read these claims if present.

---

## Next slice (when you pick this up again)

Switch repos to `~/RubyOnRails/web_scraper/`. Per the contract doc, the next workstream pair:

1. **`GET /api/v1/apps/:slug/compatibilities`** — Clerk-aware: claimed-owner sees all rows, public callers see only `visible_publicly: true`. Drives a per-app compatibility-matrix view.
2. **`PUT /api/v1/apps/:slug/compatibilities/:theme_title`** — create-or-update one compatibility row. **Override-authority guard** is the interesting bit: if existing row's `last_authored_by == "admin"` AND `claim_review_window_closes_at` is in the past (or nil), developer PUT returns `403 forbidden` with `reason: "admin_locked"`. Admin writes are unconditional and flip `last_authored_by` to `"admin"`.

Ship as a pair — same view will exercise both, share the override-authority logic. Mirror the patterns established in this session:

- Use `ClerkBaseController` for auth
- Use `CursorPagination` for the GET
- Use the existing `AppThemeCompatibility` model (`web_scraper/app/models/app_theme_compatibility.rb`)
- Add a `serialize_compatibility`-style concern if it'll be reused (currently lives private in `AppsController`)
- Mirror request-spec style from `spec/requests/api/v1/me_spec.rb` — auth wall + happy-path + auth-specific behavior

After both ship in web_scraper, switch back here and build a new `/my-apps/:slug/compatibilities` page (route + controller + view) that lists rows and lets the developer edit them.

The remaining endpoints after that pair, in priority order:
3. `DELETE /api/v1/apps/:slug/compatibilities/:theme_title`
4. `PATCH /api/v1/apps/:slug` — update claimed listing metadata
5. `POST /api/v1/apps` — claim or register a new listing (most complex; opens the claim review window, 409 conflict path, slug derivation; worth doing last)

---

## Open items / future cleanups

Not urgent, in rough order of when they become relevant:

- [ ] **Stale `bun.lock`** — deleted from working tree on 2026-05-22 (moved off bun in favor of yarn-only for Docker build). Stage the deletion when you next commit if it's still showing as deleted-but-unstaged.
- [ ] **Delete the old landing-page Cloudflare Worker** — fallback period started 2026-05-22 post-cutover; safe to delete around 2026-06-05 if `theme.watch` has stayed green.
- [ ] **Rate limiting on Clerk endpoints in shopinfo.app** — contract specifies 600/min/AppDeveloper, headers `X-RateLimit-*` on every response. Not implemented yet. Out of scope for individual endpoint PRs; worth a dedicated pass after several endpoints exist.
- [ ] **Move `SHOPINFO_API_BASE_URL` to Render's internal hostname** — once you've confirmed both services share a private network in the same Render workspace, swap the public `https://shopinfo.app/api/v1` value for the internal `http://shopinfo-web:PORT/api/v1` hostname. Faster, doesn't leave the workspace.
- [ ] **Migrate the waitlist Cloudflare Worker into Rails** — eventually. KV → a `WaitlistEntry` model (or merge into AppDeveloper) and reuse shopinfo.app's Resend setup. Not urgent; the Worker is cheap, simple, and battle-tested. Reasonable trigger: when you open real AppDeveloper sign-ups and the waitlist becomes redundant, OR when Phase 3's `AlertPreference` adds the first real local table anyway.
- [ ] **Coordinate switch to Clerk production instance** — when you're ready to actually launch for real users. Requires setting new `CLERK_FRONTEND_API` and `CLERK_PUBLISHABLE_KEY` on **both** Render services (theme-watch and shopinfo-web) at the same time so the JWT issuer matches. Existing dev-instance AppDeveloper rows would be orphaned (probably fine — test data). Production instance with Frontend API on `clerk.theme.watch` would also eliminate Clerk's handshake redirect since eTLDs would match.
- [ ] **Verified Resend FROM address** — waitlist Worker currently sends from `onboarding@resend.dev` (Resend's shared sandbox). Works for notifications to yourself, not for any future "thanks for joining" email back to subscribers. Verify `theme.watch` with Resend before sending outbound to users.
- [ ] **Cloudflare proxy decision** — after cert is live (it is), decide whether to re-enable the orange cloud (CF caching / WAF / DDoS in front of Render) or leave it as DNS-only.

---

## Session learnings worth remembering

These also got saved to memory for cross-session recall, but flagging them here too:

- **Clerk handshake without backend SDK works on apex domains.** Clerk JS sets `__session` client-side as a fallback. We can stay lightweight (`ClerkAuthenticatable` concern only) unless we ever see a redirect loop. See `memory/project-clerk-handshake-js-fallback.md`.
- **Required Clerk env vars per Render service:** `CLERK_FRONTEND_API` must be on BOTH theme-watch AND shopinfo-web with matching values. `CLERK_PUBLISHABLE_KEY` only on theme-watch. Neither needs `CLERK_SECRET_KEY`. See `memory/project-shopinfo-dual-auth.md`.
- **Never store `request.fullpath` in session for redirect-after-sign-in** — Clerk's `__clerk_handshake` URL JWT can overflow the 4KB cookie limit. Always `request.path` only. Codified in `clerk_authenticatable.rb:23` with a comment.
