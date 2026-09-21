require "net/http"

# Mirrors web_scraper/app/controllers/concerns/clerk_authenticatable.rb for JWKS
# verification, but is adapted for a browser-facing Rails app: the JWT comes from
# the Clerk-set __session cookie (or a Bearer header for API-style usage), and
# auth failures redirect to /sign-in rather than rendering JSON.
#
# JWKS handling: keys are cached for JWKS_CACHE_TTL and refreshed on expiry or
# when the JWT library asks for invalidation (unknown kid). If a refresh fails
# and a previously fetched set is still in the cache, we log a warning and keep
# verifying against the cached keys instead of signing everyone out.
module ClerkAuthenticatable
  extend ActiveSupport::Concern

  # Raised when the JWKS endpoint cannot be fetched and no cached copy exists.
  class JwksFetchError < StandardError; end

  JWKS_CACHE_KEY = "clerk:jwks".freeze
  JWKS_CACHE_TTL = 10.minutes   # how long a fetched set is considered fresh
  JWKS_STALE_TTL = 24.hours     # how long a stale set is kept as a fallback
  JWKS_OPEN_TIMEOUT = 3         # seconds
  JWKS_READ_TIMEOUT = 3         # seconds
  CLERK_SESSION_COOKIE = "__session".freeze

  included do
    helper_method :clerk_signed_in?, :clerk_user_email, :clerk_user_id, :clerk_payload
  end

  POST_SIGN_IN_SESSION_KEY = :post_sign_in_redirect

  # Reduces an untrusted return-to value to a same-origin path. Anything that is
  # not a plain absolute path (a full URL, a protocol-relative //host, a
  # backslash trick, whitespace, or a sign-in page that would loop) falls back.
  def self.safe_return_path(value, fallback:)
    return fallback unless value.is_a?(String)
    return fallback unless value.match?(%r{\A/(?![/\\])[^\s]*\z})
    return fallback if value.start_with?("/sign-in", "/sign-up")

    value
  end

  private

  def require_clerk_user!
    if clerk_signed_in?
      # The stored path has done its job once an authenticated request succeeds.
      session.delete(POST_SIGN_IN_SESSION_KEY)
      return
    end

    # `request.path` only — never `request.fullpath`. Clerk's handshake redirect
    # arrives at /dashboard with a multi-kilobyte `__clerk_handshake` JWT in the
    # query string; storing it would overflow the 4KB session cookie limit.
    session[POST_SIGN_IN_SESSION_KEY] = request.path if request.get?
    redirect_to sign_in_path
  end

  # Where Clerk should send the user after sign-in or sign-up. Read, not
  # deleted, so a sign-in page that hands off to sign-up keeps the target; the
  # key is cleared by require_clerk_user! on the first authenticated request.
  def post_sign_in_path
    ClerkAuthenticatable.safe_return_path(session[POST_SIGN_IN_SESSION_KEY], fallback: dashboard_path)
  end

  def clerk_signed_in?
    clerk_payload.present?
  end

  def clerk_payload
    return @clerk_payload if defined?(@clerk_payload)

    token = clerk_jwt
    @clerk_payload = token ? verify_clerk_jwt(token) : nil
  end

  def clerk_jwt
    bearer_token.presence || cookies[CLERK_SESSION_COOKIE].presence
  end

  def clerk_user_id
    clerk_payload&.dig("sub")
  end

  def clerk_user_email
    clerk_payload&.dig("email")
  end

  def bearer_token
    header = request.headers["Authorization"].to_s
    header.start_with?("Bearer ") ? header.sub(/^Bearer /, "") : nil
  end

  def verify_clerk_jwt(token)
    JWT.decode(
      token,
      nil,
      true,
      algorithms: ["RS256"],
      iss: clerk_issuer,
      verify_iss: true,
      jwks: clerk_jwks_loader,
    ).first
  rescue JWT::DecodeError => e
    Rails.logger.info("[Clerk] JWT verification failed: #{e.class} #{e.message}")
    nil
  end

  def clerk_issuer
    ENV.fetch("CLERK_FRONTEND_API")
  end

  def clerk_jwks_loader
    ->(options) { load_clerk_jwks(invalidate: options[:invalidate]) }
  end

  # Returns the JWKS hash. Cache entries are { jwks:, fetched_at: } and live for
  # JWKS_STALE_TTL so a stale copy is available if a refresh fails.
  def load_clerk_jwks(invalidate: false)
    cached = Rails.cache.read(JWKS_CACHE_KEY)
    cached = nil unless cached.is_a?(Hash) && cached[:jwks].is_a?(Hash) && cached[:fetched_at]

    if cached && !invalidate && cached[:fetched_at] > JWKS_CACHE_TTL.ago
      return cached[:jwks]
    end

    jwks = fetch_clerk_jwks
    Rails.cache.write(JWKS_CACHE_KEY, { jwks: jwks, fetched_at: Time.current }, expires_in: JWKS_STALE_TTL)
    jwks
  rescue JwksFetchError => e
    raise unless cached

    Rails.logger.warn(
      "[Clerk] JWKS refresh failed (#{e.message}); serving cached keys fetched at #{cached[:fetched_at].iso8601}"
    )
    cached[:jwks]
  end

  def fetch_clerk_jwks
    uri = URI.join(clerk_issuer, "/.well-known/jwks.json")

    response = Net::HTTP.start(
      uri.host, uri.port,
      use_ssl: uri.scheme == "https",
      open_timeout: JWKS_OPEN_TIMEOUT,
      read_timeout: JWKS_READ_TIMEOUT,
      write_timeout: JWKS_READ_TIMEOUT,
    ) { |http| http.get(uri.request_uri) }

    raise JwksFetchError, "HTTP #{response.code} from #{uri}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).deep_symbolize_keys
  rescue JwksFetchError
    raise
  rescue Timeout::Error, IOError, SocketError, SystemCallError, OpenSSL::SSL::SSLError, JSON::ParserError => e
    raise JwksFetchError, "#{e.class}: #{e.message} (#{uri})"
  end
end
