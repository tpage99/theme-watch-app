# Where to pick up

Living handoff doc. Update as state changes. **Last updated: 2026-05-22 (compatibilities pair shipped).**

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

**`~/RubyOnRails/web_scraper/` (compatibilities pair, 2026-05-22 PM):**
- `app/controllers/api/v1/compatibilities_controller.rb` — NEW, hybrid-auth GET + Clerk-required PUT with override-authority guard
- `app/controllers/concerns/api/v1/compatibility_serialization.rb` — NEW, shared serializer (mirrors AppListingSerialization)
- `app/controllers/api/v1/apps_controller.rb` — refactored to include new serializer concern (removed private `serialize_compatibility`)
- `app/controllers/concerns/clerk_authenticatable.rb` — added `try_authenticate_clerk_jwt` (auth-if-present, 401 on bad token, no-op on missing)
- `config/routes.rb` — added GET and PUT for `apps/:slug/compatibilities`
- `spec/requests/api/v1/compatibilities_spec.rb` — NEW, 20 examples covering auth modes, visibility filter, override-authority guard (all green)
- `docs/api/theme-watch-contract.md` — marked both endpoints as live

**`~/RubyOnRails/theme-watch-app/` (consumer side, 2026-05-22 PM):**
- `app/services/shopinfo_api.rb` — added `app_compatibilities(slug, ...)`, `update_app_compatibility(slug, theme_title, attrs)`, generic `put`, new `Forbidden < Error` class with `.reason` helper
- `app/controllers/my_app_compatibilities_controller.rb` — NEW, `index` / `create` / `update` actions
- `app/views/my_app_compatibilities/index.html.erb` — NEW, lists rows + per-row edit form + top-of-page "add row" form
- `app/views/my_apps/index.html.erb` — added "Manage compatibilities →" link on each card
- `config/routes.rb` — added GET / POST / PATCH routes under `my-apps/:slug/compatibilities`
- `NEXT-STEPS.md` — this doc

**Earlier this session (already pushed by Taylor):**
- web_scraper: `/me/apps` endpoint + shared `AppListingSerialization` concern
- theme-watch-app: `/my-apps` page, `me_apps` client method, `request.fullpath`→`request.path` Clerk handshake fix

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

## Testing plan for the compatibilities pair (do this first)

Cheapest → most thorough. Anything that's already passing in the spec suite is noted so you don't repeat it manually.

### 1. Server-side specs (already green; rerun for confidence)

```bash
cd ~/RubyOnRails/web_scraper
bundle exec rspec spec/requests/api/v1/compatibilities_spec.rb \
                  spec/requests/api/v1/apps_spec.rb \
                  spec/requests/api/v1/me_spec.rb
```

Expected: 48 examples, 0 failures. Covers:
- Hybrid GET auth modes (anonymous, owner, non-owner, invalid token)
- `visible_publicly` filtering on rows + listing visibility
- Status filter (single + comma-separated)
- 404 on private listing for anonymous, 404 on missing slug
- PUT 401 / 403 `not_owner` / 403 `admin_locked` (window-closed + window-null)
- Override allowed when review window is open
- 422 validation errors
- 201 create vs 200 update + case-insensitive `theme_title` match

### 2. Set up prod test data (one Rails console session)

You need a claimed listing + one admin-authored row to exercise the lock. From a shopinfo-web console (or local console pointed at prod DB):

```ruby
me = AppDeveloper.find_by!(clerk_user_id: "<your_clerk_sub>")   # get sub from /api/v1/me/ping
listing = AppListing.find_by!(slug: "<pick-a-real-slug>")
listing.update!(claimed_by_app_developer: me, visible_publicly: true)
listing.open_claim_review_window!(duration: 14.days)            # so the guard doesn't block your first PUT
```

(For step 5's lock test, you'll also need:)
```ruby
AppThemeCompatibility.create!(app_listing: listing, theme_title: "Sense",
                              status: "supported", last_authored_by: "admin",
                              visible_publicly: true)
```

### 3. Anonymous GET — curl, no auth

Confirms the hybrid endpoint serves public callers and filters private rows.

```bash
curl -sS https://shopinfo.app/api/v1/apps/<slug>/compatibilities | jq
curl -sS "https://shopinfo.app/api/v1/apps/<slug>/compatibilities?status=supported,needs_customization" | jq
curl -sS -o /dev/null -w "%{http_code}\n" https://shopinfo.app/api/v1/apps/does-not-exist/compatibilities
# → 404
curl -sS -o /dev/null -w "%{http_code}\n" -H "Authorization: Bearer not.a.jwt" https://shopinfo.app/api/v1/apps/<slug>/compatibilities
# → 401
```

### 4. Authed end-to-end in the browser

1. Sign in at https://theme.watch
2. `/my-apps` → the claimed listing card should now show **"Manage compatibilities →"**
3. Click it → land on `/my-apps/<slug>/compatibilities`
4. **Create**: fill the "Add a compatibility row" form (`theme_title: Dawn`, status: supported, visible_publicly: ✓) → submit → row appears + green flash
5. **Update**: change status on the row you just made → submit → green flash, row reflects new status
6. **Re-verify public visibility**: rerun the anonymous curl from step 3 — the new public row should appear. Toggle the row to private in the UI, submit, recurl — it disappears for anonymous.

### 5. Edge cases (the interesting ones)

**Override-authority guard:**
1. Console: close the review window — `listing.close_claim_review_window!`
2. In the browser, edit the **Sense** row (the admin-authored one) → redirects back with the amber flash: *"This row was last edited by a shopinfo.app admin and the claim review window has closed…"*
3. Reopen: `listing.open_claim_review_window!` → retry the same edit → succeeds, and the row's "Last edited by …" line flips from `admin` to `developer`.

**Non-owner forbidden:** sign in as a different Clerk user (incognito + a second GitHub account works), navigate directly to `/my-apps/<your-slug>/compatibilities` — GET succeeds but only public rows show (treated as anonymous-style). A direct PATCH would return 403 `not_owner`, but the UI doesn't expose the link to non-owners since the card isn't on their `/my-apps`.

**Validation error:** curl or DevTools — send `status=garbage` → expect 422 `validation_failed`. UI shows an amber flash with "shopinfo.app returned HTTP 422".

### 6. When something fails, look here

- **theme.watch Render logs** — controller-level errors, Clerk JWT issues
- **shopinfo-web Render logs** — API-level errors, issuer mismatches, model validations
- **Browser DevTools Network tab** — PATCH/POST payloads, `__session` cookie, response bodies
- **Common gotchas:**
  - 401 from theme.watch despite being signed in → `CLERK_FRONTEND_API` mismatch between services (the bug that bit us last session)
  - 404 on a listing you just claimed → forgot `visible_publicly: true` AND hitting it as anonymous
  - Form submits but nothing changes → flash should be amber if a Faraday error was rescued; if there's no flash and no change, check whether `params.permit` is dropping a field

---

## Next slice (after testing passes)

1. **`DELETE /api/v1/apps/:slug/compatibilities/:theme_title`** — same override-authority rules as PUT. Smallest remaining endpoint; ship next. Mirror `CompatibilitiesController#update` for the auth/guard logic. On the theme-watch-app side, add a delete button per row.
2. **`PATCH /api/v1/apps/:slug`** — update claimed listing metadata (name, description, category, icon_url, support_url, docs_url, visible_publicly). Drives an "edit listing" page off the My Apps card. No override-authority guard but still needs an ownership check.
3. **`POST /api/v1/apps`** — claim or register a new listing (most complex; opens the claim review window, 409 conflict path, slug derivation; worth doing last).

Patterns established this session — reuse them:

- `ClerkAuthenticatable#try_authenticate_clerk_jwt` for any future hybrid endpoint
- `Api::V1::CompatibilitySerialization` concern for any endpoint that returns a compatibility row
- `caller_is_owner?(listing)` helper pattern (currently private in `CompatibilitiesController`) — extract to a shared concern if a third controller needs it
- On theme-watch-app: `ShopinfoApi::Forbidden#reason` for surfacing API error codes to users

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
- **Hybrid-auth API endpoints** (anonymous + Clerk owner from the same path) are workable: include `ClerkAuthenticatable`, `skip_before_action :authenticate_clerk_jwt!`, then `before_action :try_authenticate_clerk_jwt, only: [:read_action]`. Owner is identified by `current_app_developer&.id == listing.claimed_by_app_developer_id`. See `Api::V1::CompatibilitiesController` in web_scraper for the working pattern.
