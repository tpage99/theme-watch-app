require "test_helper"

# Exercises ClerkAuthenticatable through a real authenticated route (/alerts,
# which renders without calling shopinfo.app). See ClerkSessionTestHelper for
# the keypair and JWKS stubbing. The sidebar prints clerk_user_id in a title
# attribute, which is how these tests observe which identity was accepted.
class ClerkAuthenticatableTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  def assert_signed_in_as(user_id)
    assert_response :success
    assert_select "[title=?]", user_id
  end

  def assert_rejected
    assert_redirected_to sign_in_path
  end

  # --- accepting and rejecting tokens --------------------------------------

  test "a valid session cookie signs the user in and sets clerk_user_id" do
    clerk_sign_in(sub: "user_abc")

    get alerts_path

    assert_signed_in_as "user_abc"
    assert_requested :get, CLERK_JWKS_URL, times: 1
  end

  test "a missing token redirects to sign-in and remembers the path" do
    get alerts_path

    assert_rejected
    assert_equal alerts_path, session[:post_sign_in_redirect]
  end

  test "an expired token is rejected" do
    clerk_sign_in(exp: 1.hour.ago.to_i, iat: 2.hours.ago.to_i)

    get alerts_path

    assert_rejected
  end

  test "a token from a different issuer is rejected" do
    clerk_sign_in(iss: "https://someone-else.example")

    get alerts_path

    assert_rejected
  end

  test "a token signed with a different key is rejected" do
    stub_clerk_jwks
    rogue_key = OpenSSL::PKey::RSA.generate(2048)
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = clerk_token(key: rogue_key)

    get alerts_path

    assert_rejected
  end

  test "a token with an unknown kid triggers one JWKS refresh and is then rejected" do
    stub_clerk_jwks
    rogue_key = OpenSSL::PKey::RSA.generate(2048)
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = clerk_token(key: rogue_key, kid: "unknown-kid")

    get alerts_path

    assert_rejected
    assert_requested :get, CLERK_JWKS_URL, times: 2
  end

  test "a malformed cookie is rejected without fetching the JWKS" do
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = "not.a.jwt"

    get alerts_path

    assert_rejected
    assert_not_requested :get, CLERK_JWKS_URL
  end

  test "a Bearer header takes precedence over the session cookie" do
    clerk_sign_in(sub: "user_from_cookie")

    get alerts_path, headers: { "Authorization" => "Bearer #{clerk_token(sub: 'user_from_header')}" }

    assert_signed_in_as "user_from_header"
  end

  test "an invalid Bearer header is not rescued by a valid cookie" do
    clerk_sign_in(sub: "user_from_cookie")

    get alerts_path, headers: { "Authorization" => "Bearer garbage" }

    assert_rejected
  end

  # --- JWKS caching and failure ---------------------------------------------

  test "JWKS is cached between requests" do
    clerk_sign_in

    get alerts_path
    get alerts_path

    assert_response :success
    assert_requested :get, CLERK_JWKS_URL, times: 1
  end

  test "a JWKS fetch failure with a warm cache does not sign the user out" do
    clerk_sign_in
    get alerts_path
    assert_response :success

    # Age the cached entry past the fresh TTL so the next request tries to
    # refresh, then make the refresh time out.
    entry = Rails.cache.read(ClerkAuthenticatable::JWKS_CACHE_KEY)
    Rails.cache.write(ClerkAuthenticatable::JWKS_CACHE_KEY,
                      entry.merge(fetched_at: (ClerkAuthenticatable::JWKS_CACHE_TTL + 1.minute).ago))
    stub_request(:get, CLERK_JWKS_URL).to_timeout

    get alerts_path

    assert_response :success
    assert_requested :get, CLERK_JWKS_URL, times: 2
  end

  test "a JWKS fetch failure with a cold cache raises rather than silently signing out" do
    stub_request(:get, CLERK_JWKS_URL).to_timeout
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = clerk_token

    assert_raises(ClerkAuthenticatable::JwksFetchError) { get alerts_path }
  end

  test "a JWKS fetch that returns a non-200 with a cold cache raises" do
    stub_request(:get, CLERK_JWKS_URL).to_return(status: 503)
    cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE] = clerk_token

    assert_raises(ClerkAuthenticatable::JwksFetchError) { get alerts_path }
  end

  test "the JWKS request uses short timeouts" do
    assert_equal 3, ClerkAuthenticatable::JWKS_OPEN_TIMEOUT
    assert_equal 3, ClerkAuthenticatable::JWKS_READ_TIMEOUT
  end
end
