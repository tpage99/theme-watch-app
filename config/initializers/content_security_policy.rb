# Be sure to restart your server when you modify this file.

# Content Security Policy for theme.watch.
#
# Third parties, and why each is here:
#   Clerk Frontend API host   script (clerk.browser.js and its chunks), connect
#                             (session, sign-in), frame (handshake), img
#   img.clerk.com             avatars and provider logos inside Clerk components
#   challenges.cloudflare.com Clerk's bot-protection widget (script + frame)
#   cdn.usefathom.com         analytics script; its beacon goes to the same host
#   fonts.googleapis.com      DM Sans / JetBrains Mono stylesheet
#   fonts.gstatic.com         the font files that stylesheet references
#   shopinfo.app              app listing icons on My Apps
#   waitlist Worker           the landing page waitlist POST (fetch)
#
# Clerk injects <style> elements into its mounted components, so style-src
# must allow 'unsafe-inline'. Nonces are therefore applied to script-src only;
# adding style-src to the nonce directives would make browsers ignore
# 'unsafe-inline' and break the sign-in UI.
#
# The Clerk host is read per request (lambdas) rather than at boot, so the
# policy follows CLERK_FRONTEND_API in every environment, including tests.
#
# Rollout: shipped as report-only on 2026-09-21. After one production deploy
# with a clean console on landing, sign-in, dashboard, My Apps and
# compatibilities, set `content_security_policy_report_only` to false.

Rails.application.configure do
  clerk_host = -> { ENV["CLERK_FRONTEND_API"].presence&.chomp("/") }
  waitlist_worker = "https://themewatch-waitlist.taylor-d3a.workers.dev"

  config.content_security_policy do |policy|
    policy.default_src :self
    policy.base_uri    :self
    policy.object_src  :none
    policy.form_action :self

    policy.script_src  :self, clerk_host, "https://cdn.usefathom.com", "https://challenges.cloudflare.com"
    policy.connect_src :self, clerk_host, "https://cdn.usefathom.com", waitlist_worker
    policy.frame_src   :self, clerk_host, "https://challenges.cloudflare.com"
    policy.img_src     :self, :data, clerk_host, "https://img.clerk.com", "https://shopinfo.app", "https://cdn.usefathom.com"
    policy.style_src   :self, :unsafe_inline, "https://fonts.googleapis.com"
    policy.font_src    :self, "https://fonts.gstatic.com"
    policy.worker_src  :self, :blob
  end

  # Per-request nonce for the inline JSON-LD block on the landing page and
  # any future inline script. Turbo reads it from the csp-nonce meta tag.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  config.content_security_policy_nonce_directives = %w[script-src]

  # Report violations without enforcing the policy. Flip to false after one
  # clean production deploy (see rollout note above).
  config.content_security_policy_report_only = true
end
