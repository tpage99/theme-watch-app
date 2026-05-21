require "net/http"

# Mirrors web_scraper/app/controllers/concerns/clerk_authenticatable.rb for JWKS
# verification, but is adapted for a browser-facing Rails app: the JWT comes from
# the Clerk-set __session cookie (or a Bearer header for API-style usage), and
# auth failures redirect to /sign-in rather than rendering JSON.
module ClerkAuthenticatable
  extend ActiveSupport::Concern

  JWKS_CACHE_KEY = "clerk:jwks".freeze
  JWKS_CACHE_TTL = 10.minutes
  CLERK_SESSION_COOKIE = "__session".freeze

  included do
    helper_method :clerk_signed_in?, :clerk_user_email, :clerk_user_id, :clerk_payload
  end

  private

  def require_clerk_user!
    return if clerk_signed_in?

    session[:post_sign_in_redirect] = request.fullpath if request.get?
    redirect_to sign_in_path
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
    ->(options) {
      Rails.cache.fetch(JWKS_CACHE_KEY, expires_in: JWKS_CACHE_TTL, force: options[:invalidate]) do
        fetch_clerk_jwks
      end
    }
  end

  def fetch_clerk_jwks
    uri = URI.join(clerk_issuer, "/.well-known/jwks.json")
    response = Net::HTTP.get_response(uri)
    raise "JWKS fetch failed: HTTP #{response.code}" unless response.is_a?(Net::HTTPSuccess)

    JSON.parse(response.body).deep_symbolize_keys
  end
end
