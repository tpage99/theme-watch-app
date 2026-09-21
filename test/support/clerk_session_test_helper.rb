require "openssl"

# Signs the test in as a Clerk user without a Clerk instance. Generates an RSA
# keypair per test, serves the public key from a stubbed JWKS URL, and signs
# real RS256 tokens that ClerkAuthenticatable verifies end to end.
#
# Also pins SHOPINFO_API_BASE_URL to a fake host so a test never talks to the
# real shopinfo.app, and swaps Rails.cache for a MemoryStore so JWKS caching
# behaves the way it does in production.
module ClerkSessionTestHelper
  CLERK_ISSUER = "https://clerk.test.example".freeze
  CLERK_JWKS_URL = "#{CLERK_ISSUER}/.well-known/jwks.json".freeze
  CLERK_KID = "test-key-1".freeze
  SHOPINFO_BASE_URL = "https://shopinfo.test/api/v1".freeze

  def self.included(base)
    base.setup :clerk_test_setup
    base.teardown :clerk_test_teardown
  end

  def clerk_test_setup
    @clerk_original_env = ENV.slice("CLERK_FRONTEND_API", "SHOPINFO_API_BASE_URL")
    ENV["CLERK_FRONTEND_API"] = CLERK_ISSUER
    ENV["SHOPINFO_API_BASE_URL"] = SHOPINFO_BASE_URL

    @clerk_original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    @clerk_private_key = OpenSSL::PKey::RSA.generate(2048)
  end

  def clerk_test_teardown
    @clerk_original_env.each { |k, v| ENV[k] = v }
    Rails.cache = @clerk_original_cache
  end

  def clerk_jwks_body
    { keys: [JWT::JWK.new(@clerk_private_key.public_key, kid: CLERK_KID).export] }.to_json
  end

  def stub_clerk_jwks
    stub_request(:get, CLERK_JWKS_URL)
      .to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: clerk_jwks_body)
  end

  # Returns a signed session token. Pass claim overrides, e.g. exp: 1.hour.ago.to_i.
  # The special keys :key and :kid sign with a different RSA key or key id to
  # simulate a token from another Clerk instance. Declared without keyword
  # arguments on purpose so `clerk_token(sub: "x")` is treated as claims.
  def clerk_token(claims = {})
    claims = claims.dup
    key = claims.delete(:key) || @clerk_private_key
    kid = claims.delete(:kid) || CLERK_KID
    now = Time.now.to_i
    payload = { iss: CLERK_ISSUER, sub: "user_test", iat: now, exp: now + 300 }.merge(claims)
    JWT.encode(payload, key, "RS256", kid: kid)
  end

  # Stubs the JWKS and sets the session cookie so the next request is signed in.
  def clerk_sign_in(claims = {})
    stub_clerk_jwks
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = clerk_token(claims)
  end

  def shopinfo_url(path)
    "#{SHOPINFO_BASE_URL}#{path}"
  end

  def json_response(status, body)
    { status: status, headers: { "Content-Type" => "application/json" }, body: body.to_json }
  end
end
