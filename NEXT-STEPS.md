# Where to pick up

Living handoff doc. Update as state changes. **Last updated: 2026-05-22 (post-DNS cutover).**

For project context, conventions, and architectural decisions see [CLAUDE.md](CLAUDE.md). For the original 9-step bootstrap plan and DNS cutover sequence see `~/RubyOnRails/web_scraper/docs/theme-watch-app-bootstrap.md`.

---

## Current state

**Milestone 1: complete.** Rails 7.1 app scaffolded, landing-page parity with the old Cloudflare-served `theme.watch`, Clerk auth wired via JWKS verification, Faraday client talking to shopinfo.app's `/api/v1/me/ping`, sidebar shell with Dashboard / My Apps / Alerts / Settings, deployed to Render in the shopinfo.app workspace + project.

**DNS cutover: complete.** `https://theme.watch` now resolves to the Render-hosted Rails app. Auth end-to-end verified against production shopinfo.app. Clerk dev instance accepts the real domain without extra config — no `pk_live_…` instance needed yet. Old landing-page Cloudflare Worker left deployed-but-unrouted as a ~2-week fallback (delete around early June 2026).

---

## Immediate next move

**`GET /api/v1/me/apps` is live both sides** (2026-05-22). shopinfo.app endpoint shipped in web_scraper (`Api::V1::MeController#apps`, `Api::V1::AppListingSerialization` concern, 6 request specs). theme.watch's `MyAppsController#index` now calls it, renders claimed AppListings as cards with verified/private badges, empty state if none, amber error panel if shopinfo.app is unreachable. Tested locally against… (verify once Taylor reloads `/my-apps` — he has no claimed apps yet, so the empty state is what he'll see until someone admin-assigns him one in shopinfo.app).

**Workstream 1 — remaining Clerk-auth endpoints on shopinfo.app.** In rough priority order, all per `~/RubyOnRails/web_scraper/docs/api/theme-watch-contract.md`:

1. `GET /api/v1/apps/:slug/compatibilities` (Clerk-aware: owner sees all, public sees visible-only) — unlocks the per-app "Theme compatibility" matrix view in theme.watch.
2. `PUT /api/v1/apps/:slug/compatibilities/:theme_title` (with override-authority guard) — unlocks the actual editing UX. Most product-meaningful endpoint of the bunch.
3. `DELETE /api/v1/apps/:slug/compatibilities/:theme_title`.
4. `PATCH /api/v1/apps/:slug` (update claimed listing — name, description, support_url, etc.) — unlocks the app settings page.
5. `POST /api/v1/apps` (claim or register a new listing) — unlocks the self-serve claim flow. Most complex of the bunch (open-claim-review-window logic, 409 conflict path, derive slug). Worth doing last so the read/edit flows are battle-tested first.

Each new shopinfo.app endpoint unlocks UI work back in this repo.

**Suggested next slice:** endpoints 1 + 2 together (read + write for compatibilities) since they share the override-authority logic and the same view will exercise both. Ship them as a pair, then wire up a `/my-apps/:slug/compatibilities` page in theme.watch.

---

## Open items / future cleanups

Not urgent, in rough order of when they become relevant:

- [ ] **Stale `bun.lock`** — deleted from the working tree on 2026-05-22 (we moved off bun in favor of yarn-only for the Docker build). Stage the deletion when you next commit.
- [ ] **Add `email` claim to Clerk session token** — Clerk dashboard → Sessions → Customize session token. Currently the dashboard shows "Hello, developer." instead of an email because the JWT doesn't include the email claim. Two-line config fix.
- [ ] **Delete the old landing-page Cloudflare Worker** — fallback period started 2026-05-22 post-cutover; safe to delete around 2026-06-05 if `theme.watch` has stayed green.
- [ ] **Move `SHOPINFO_API_BASE_URL` to Render's internal hostname** — once you've confirmed both services share a private network in the same Render workspace, swap the public `https://shopinfo.app/api/v1` value for the internal `http://shopinfo-web:PORT/api/v1` hostname. Faster, doesn't leave the workspace.
- [ ] **Migrate the waitlist Cloudflare Worker into Rails** — eventually. KV → a `WaitlistEntry` model (or merge into AppDeveloper) and reuse shopinfo.app's Resend setup. Not urgent; the Worker is cheap, simple, and battle-tested. Reasonable trigger: when you open real AppDeveloper sign-ups and the waitlist becomes redundant, OR when Phase 3's `AlertPreference` adds the first real local table anyway.
- [ ] **Coordinate switch to Clerk production instance** — when you're ready to actually launch theme.watch for real users. Requires setting new `CLERK_FRONTEND_API` and `CLERK_PUBLISHABLE_KEY` env vars on **both** Render services (theme-watch and shopinfo-web) at the same time so the JWT issuer matches. Existing dev-instance AppDeveloper rows would be orphaned (probably fine — they're test data).
- [ ] **Verified Resend FROM address** — the waitlist Worker currently sends from `onboarding@resend.dev` (Resend's shared sandbox). Works for notifications to yourself, not for any future "thanks for joining" email back to subscribers. Verify a domain like `theme.watch` with Resend before sending outbound to users.
- [ ] **Cloudflare proxy decision** — after the cert is live, decide whether to re-enable the orange cloud (CF caching / WAF / DDoS in front of Render) or leave it as DNS-only.
