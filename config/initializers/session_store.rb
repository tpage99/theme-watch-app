# Be sure to restart your server when you modify this file.

# theme.watch has no database; the session is an encrypted cookie holding only
# the flash and the post-sign-in return path. Settings are spelled out here so
# they are visible rather than inherited from framework defaults.
Rails.application.config.session_store :cookie_store,
  key: "_theme_watch_session",
  same_site: :lax,
  secure: Rails.env.production?
