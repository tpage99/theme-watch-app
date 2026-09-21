require "test_helper"

# Exercises ClerkAuthenticatable through a real authenticated route (/alerts,
# which renders without calling shopinfo.app). See ClerkSessionTestHelper for
# the keypair and JWKS stubbing.
class ClerkAuthenticatableTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  test "a valid session cookie signs the user in" do
    clerk_sign_in

    get alerts_path

    assert_response :success
    assert_requested :get, CLERK_JWKS_URL, times: 1
  end

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
