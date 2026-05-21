# theme.watch — App Developer Portal

theme.watch is the developer-facing Rails app for the shopinfo.app ecosystem. App developers sign in here to claim their Shopify app listing, mark theme compatibility, manage public visibility, and (Phase 3) receive theme version alerts.

## Critical context

- **shopinfo.app is the source of truth.** This app holds no business data of its own. All reads and mutations go through `https://shopinfo.app/api/v1/*` via the Faraday client at `app/services/shopinfo_api.rb`.
- **API contract**: `~/RubyOnRails/web_scraper/docs/api/theme-watch-contract.md` — authoritative. Don't invent endpoints; if one's missing, flag it and we add it to the contract first.
- **Auth**: Clerk-issued JWT, same provider as shopinfo.app. JWT is forwarded on every API call as `Authorization: Bearer <jwt>`. The shopinfo.app side auto-upserts an `AppDeveloper` record on first hit.
- **No local DB** in Phase 2. Sessions in encrypted cookies.
- **Companion repo**: `~/RubyOnRails/web_scraper/` — the shopinfo.app Rails app and API.

## Non-negotiables (inherited from shopinfo.app conventions)

### Transparency
- NEVER use fake or inflated metrics. Display real counts only.
- Marketing copy focuses on product value, not fabricated social proof.

### Performance & event handling
- Prefer CSS over JavaScript for visual interactions (hover, focus, transitions).
- Use `turbo:load` for event listeners, NOT `DOMContentLoaded`.

### HTML & accessibility
- Semantic HTML: `<nav>`, `<ul>`, `<li>` for navigation, not `<div>`s.
- Real links (`<a href="/path">`) for navigation. Never `<a href="#">`. Use `<button>` for actions that don't change the URL.
- All interactive elements must be keyboard accessible with visible focus states and logical tab order.

### Copy conventions
- Refer to the product as `theme.watch` (lowercase, with the dot).
- Refer to the API source as `shopinfo.app` (lowercase, with the dot).
- Do not use `&` in copy.

### Dev server
- NEVER start or stop the development server. It runs persistently in the background. Prompt the user if a server action is needed.

## Stack

- Rails 7.1+, Hotwire (Turbo + Stimulus), Tailwind CSS (v4, CSS-first config), esbuild
- Clerk for auth (JWT verification via JWKS — pattern mirrors `web_scraper/app/controllers/concerns/clerk_authenticatable.rb`)
- Faraday for the shopinfo.app API client
- Deployed on Render (Docker web service, Oregon region, private network to shopinfo.app)

## Design tokens

- Brand palette: Tailwind `tw-*` (teal, 50–950). Defined via `@theme` in `app/assets/stylesheets/application.tailwind.css`.
- Body font: DM Sans. Mono: JetBrains Mono.
- Signature CSS effects (`.gradient-mesh`, `.grain`, `.border-grid`, fade animations) live in the global stylesheet — lifted from the original landing page.

## Key paths

- API client: `app/services/shopinfo_api.rb`
- Clerk concern: `app/controllers/concerns/clerk_authenticatable.rb`
- Layout shell: `app/views/layouts/application.html.erb`
- Landing: `app/views/pages/landing.html.erb`
