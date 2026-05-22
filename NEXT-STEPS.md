# Where to pick up

Living handoff doc. Update as state changes. **Last updated: 2026-05-22.**

For project context, conventions, and architectural decisions see [CLAUDE.md](CLAUDE.md). For the original 9-step bootstrap plan and DNS cutover sequence see `~/RubyOnRails/web_scraper/docs/theme-watch-app-bootstrap.md`.

---

## Current state

**Milestone 1: complete.** Rails 7.1 app scaffolded, landing-page parity with the old Cloudflare-served `theme.watch`, Clerk auth wired via JWKS verification, Faraday client talking to shopinfo.app's `/api/v1/me/ping`, sidebar shell with Dashboard / My Apps / Alerts / Settings, deployed to a Render preview URL (`theme-watch-app.onrender.com`) in the shopinfo.app workspace + project.

Auth end-to-end verified locally and on Render preview against production shopinfo.app. Clerk dev instance accepts onrender.com origins without extra config — no `pk_live_…` instance is needed yet.

---

## Immediate next move (out of band)

**DNS cutover to Render.** Per `theme-watch-app-bootstrap.md` step 9, the ⏸ checkpoint is met:

1. Add `theme.watch` as a custom domain in Render's theme-watch service settings
2. Render returns a CNAME/A target
3. Update DNS at registrar (Cloudflare) — point `theme.watch` records at Render
4. **Cloudflare proxy off** (orange cloud → grey) during initial cert issuance so Render can verify the domain and issue the Let's Encrypt cert directly. Can flip proxy back on after the cert is live if you want CF caching/WAF in front.
5. Wait 5–15 min for propagation and cert issuance
6. Verify `https://theme.watch` loads the new app + Clerk sign-in still works on the real domain
7. Leave the **old landing-page Cloudflare Worker deployed-but-unrouted** for ~2 weeks as fallback, then delete

The **waitlist Cloudflare Worker** at `themewatch-waitlist.taylor-d3a.workers.dev` is independent of the DNS flip — it stays running, CORS is wide-open (`*`), the Stimulus controller in `app/javascript/controllers/waitlist_controller.js` POSTs directly to it. No code change needed for cutover.

---

## After DNS cutover — switch repos

Next workstream lives in **`~/RubyOnRails/web_scraper/`**, not here.

**Workstream 1 — Clerk-auth write endpoints on shopinfo.app.** Per the phase-2 doc, recommended first endpoint:

- `GET /api/v1/me/apps` — mirrors the `/me/ping` pattern, simplest to scaffold. Returns claimed AppListings for the current AppDeveloper. Once this is live, wire it into theme.watch's `MyAppsController#index` (currently a placeholder) and the page lights up with real data.

After that, layer the rest of the contract from `~/RubyOnRails/web_scraper/docs/api/theme-watch-contract.md`:

- `POST /api/v1/apps` (claim or register)
- `PATCH /api/v1/apps/:slug` (update claimed listing)
- `PUT /api/v1/apps/:slug/compatibilities/:theme_title` (compatibility matrix — with override-authority guard)
- `DELETE /api/v1/apps/:slug/compatibilities/:theme_title`
- `GET /api/v1/apps/:slug/compatibilities`

Each new shopinfo.app endpoint unlocks UI work back in this repo.

---

## Open items / future cleanups

Not urgent, in rough order of when they become relevant:

- [ ] **Stale `bun.lock`** — deleted from the working tree on 2026-05-22 (we moved off bun in favor of yarn-only for the Docker build). Stage the deletion when you next commit.
- [ ] **Add `email` claim to Clerk session token** — Clerk dashboard → Sessions → Customize session token. Currently the dashboard shows "Hello, developer." instead of an email because the JWT doesn't include the email claim. Two-line config fix.
- [ ] **Delete the old landing-page Cloudflare Worker** — after the ~2-week fallback period post-DNS cutover.
- [ ] **Move `SHOPINFO_API_BASE_URL` to Render's internal hostname** — once you've confirmed both services share a private network in the same Render workspace, swap the public `https://shopinfo.app/api/v1` value for the internal `http://shopinfo-web:PORT/api/v1` hostname. Faster, doesn't leave the workspace.
- [ ] **Migrate the waitlist Cloudflare Worker into Rails** — eventually. KV → a `WaitlistEntry` model (or merge into AppDeveloper) and reuse shopinfo.app's Resend setup. Not urgent; the Worker is cheap, simple, and battle-tested. Reasonable trigger: when you open real AppDeveloper sign-ups and the waitlist becomes redundant, OR when Phase 3's `AlertPreference` adds the first real local table anyway.
- [ ] **Coordinate switch to Clerk production instance** — when you're ready to actually launch theme.watch for real users. Requires setting new `CLERK_FRONTEND_API` and `CLERK_PUBLISHABLE_KEY` env vars on **both** Render services (theme-watch and shopinfo-web) at the same time so the JWT issuer matches. Existing dev-instance AppDeveloper rows would be orphaned (probably fine — they're test data).
- [ ] **Verified Resend FROM address** — the waitlist Worker currently sends from `onboarding@resend.dev` (Resend's shared sandbox). Works for notifications to yourself, not for any future "thanks for joining" email back to subscribers. Verify a domain like `theme.watch` with Resend before sending outbound to users.
- [ ] **Cloudflare proxy decision** — after the cert is live, decide whether to re-enable the orange cloud (CF caching / WAF / DDoS in front of Render) or leave it as DNS-only.
