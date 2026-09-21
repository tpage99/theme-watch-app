require "test_helper"
require "openssl"

# Exercises ClerkAuthenticatable through a real authenticated route (/alerts,
# which renders without calling shopinfo.app). Tokens are signed with a keypair
# generated here and the Clerk JWKS endpoint is stubbed with WebMock.
class ClerkAuthenticatableTest < ActionDispatch::IntegrationTest
  ISSUER = "https://clerk.test.example".freeze
  JWKS_URL = "#{ISSUER}/.well-known/jwks.json".freeze
  KID = "test-key-1".freeze

  setup do
    @original_issuer = ENV["CLERK_FRONTEND_API"]
    ENV["CLERK_FRONTEND_API"] = ISSUER

    @original_cache = Rails.cache
    Rails.cache = ActiveSupport::Cache::MemoryStore.new

    @private_key = OpenSSL::PKey::RSA.generate(2048)
    @jwks_body = { keys: [JWT::JWK.new(@private_key.public_key, kid: KID).export] }.to_json
  end

  teardown do
    ENV["CLERK_FRONTEND_API"] = @original_issuer
    Rails.cache = @original_cache
  end

  def sign(payload = {})
    now = Time.now.to_i
    claims = { iss: ISSUER, sub: "user_test", iat: now, exp: now + 300 }.merge(payload)
    JWT.encode(claims, @private_key, "RS256", kid: KID)
  end

  def stub_jwks_ok
    stub_request(:get, JWKS_URL).to_return(status: 200, headers: { "Content-Type" => "application/json" }, body: @jwks_body)
  end

  test "a valid session cookie signs the user in" do
    stub_jwks_ok
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = sign

    get alerts_path

    assert_response :success
    assert_requested :get, JWKS_URL, times: 1
  end

  test "JWKS is cached between requests" do
    stub_jwks_ok
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = sign

    get alerts_path
    get alerts_path

    assert_response :success
    assert_requested :get, JWKS_URL, times: 1
  end

  test "a JWKS fetch failure with a warm cache does not sign the user out" do
    stub_jwks_ok
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = sign
    get alerts_path
    assert_response :success

    # Age the cached entry past the fresh TTL so the next request tries to
    # refresh, then make the refresh time out.
    entry = Rails.cache.read(ClerkAuthenticatable::JWKS_CACHE_KEY)
    Rails.cache.write(ClerkAuthenticatable::JWKS_CACHE_KEY,
                      entry.merge(fetched_at: (ClerkAuthenticatable::JWKS_CACHE_TTL + 1.minute).ago))
    stub_request(:get, JWKS_URL).to_timeout

    get alerts_path

    assert_response :success
    assert_requested :get, JWKS_URL, times: 2
  end

  test "a JWKS fetch failure with a cold cache raises rather than silently signing out" do
    stub_request(:get, JWKS_URL).to_timeout
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = sign

    assert_raises(ClerkAuthenticatable::JwksFetchError) { get alerts_path }
  end

  test "a JWKS fetch that returns a non-200 with a cold cache raises" do
    stub_request(:get, JWKS_URL).to_return(status: 503)
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = sign

    assert_raises(ClerkAuthenticatable::JwksFetchError) { get alerts_path }
  end

  test "the JWKS request uses short timeouts" do
    assert_equal 3, ClerkAuthenticatable::JWKS_OPEN_TIMEOUT
    assert_equal 3, ClerkAuthenticatable::JWKS_READ_TIMEOUT
  end
end
