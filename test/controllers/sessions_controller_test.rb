require "test_helper"

class SessionsControllerTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  def after_sign_in_url
    css_select("[data-clerk-mount-mount-value=sign-in]").first&.[]("data-clerk-mount-after-sign-in-url-value")
  end

  def after_sign_up_url
    css_select("[data-clerk-mount-mount-value=sign-up]").first&.[]("data-clerk-mount-after-sign-up-url-value")
  end

  # --- return-to flow ---------------------------------------------------------

  test "sign-in defaults to the dashboard when nothing was requested" do
    get sign_in_path

    assert_response :success
    assert_equal dashboard_path, after_sign_in_url
  end

  test "a direct hit on a protected page is remembered and handed to Clerk on sign-in" do
    target = my_app_compatibilities_path("foo")

    get target
    assert_redirected_to sign_in_path

    get sign_in_path
    assert_equal target, after_sign_in_url
  end

  test "sign-up receives the same return path as sign-in" do
    get my_apps_path
    get sign_in_path
    get sign_up_path

    assert_equal my_apps_path, after_sign_up_url
  end

  test "the return path survives visiting sign-in and is cleared once a signed-in request succeeds" do
    get my_apps_path
    get sign_in_path
    assert_equal my_apps_path, after_sign_in_url

    clerk_sign_in
    get alerts_path
    assert_response :success

    get sign_in_path
    assert_equal dashboard_path, after_sign_in_url
  end

  test "non-GET hits on protected pages are not remembered" do
    post my_app_compatibilities_path("foo"), params: { theme_title: "Dawn" }
    assert_redirected_to sign_in_path

    get sign_in_path
    assert_equal dashboard_path, after_sign_in_url
  end

  # --- sign-out ------------------------------------------------------------------

  CLERK_REVOKE_URL = %r{\Ahttps://api\.clerk\.com/v1/sessions/[^/]+/revoke\z}

  def with_clerk_secret_key(value)
    original = ENV["CLERK_SECRET_KEY"]
    ENV["CLERK_SECRET_KEY"] = value
    yield
  ensure
    original.nil? ? ENV.delete("CLERK_SECRET_KEY") : ENV["CLERK_SECRET_KEY"] = original
  end

  test "the sidebar renders sign-out as a real DELETE form" do
    clerk_sign_in
    get alerts_path

    assert_response :success
    assert_select "form[action=?][method=post]", sign_out_path do
      assert_select "input[name=_method][value=delete]"
      assert_select "button[type=submit]", text: "Sign out"
    end
  end

  test "sign-out expires the Clerk session cookie and redirects home" do
    clerk_sign_in
    get alerts_path
    assert_response :success

    delete sign_out_path

    assert_redirected_to root_path
    assert_response :see_other
    assert cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE].blank?,
           "expected __session to be expired"
    assert_match(/__session=;/, response.headers["Set-Cookie"].to_s)

    get alerts_path
    assert_redirected_to sign_in_path
  end

  test "sign-out resets the Rails session" do
    get my_apps_path # stores a return path
    delete sign_out_path

    get sign_in_path
    assert_equal dashboard_path, after_sign_in_url
  end

  test "sign-out works when nobody is signed in" do
    delete sign_out_path
    assert_redirected_to root_path
  end

  test "sign-out does not call Clerk when no secret key is configured" do
    with_clerk_secret_key(nil) do
      clerk_sign_in(sid: "sess_123")
      delete sign_out_path
    end

    assert_redirected_to root_path
    assert_not_requested :post, CLERK_REVOKE_URL
  end

  test "sign-out revokes the Clerk session when the secret key is configured" do
    revoke = stub_request(:post, "https://api.clerk.com/v1/sessions/sess_123/revoke")
      .with(headers: { "Authorization" => "Bearer sk_test_abc" })
      .to_return(json_response(200, { id: "sess_123", status: "revoked" }))

    with_clerk_secret_key("sk_test_abc") do
      clerk_sign_in(sid: "sess_123")
      delete sign_out_path
    end

    assert_requested revoke
    assert_redirected_to root_path
    assert cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE].blank?
  end

  test "sign-out still completes locally when the Clerk revoke fails" do
    stub_request(:post, "https://api.clerk.com/v1/sessions/sess_123/revoke")
      .to_return(json_response(500, { errors: [{ message: "boom" }] }))

    with_clerk_secret_key("sk_test_abc") do
      clerk_sign_in(sid: "sess_123")
      delete sign_out_path
    end

    assert_redirected_to root_path
    assert cookies[ClerkAuthenticatable::CLERK_SESSION_COOKIE].blank?
  end

  test "sign-out skips the revoke call when the token carries no session id" do
    with_clerk_secret_key("sk_test_abc") do
      clerk_sign_in
      delete sign_out_path
    end

    assert_redirected_to root_path
    assert_not_requested :post, CLERK_REVOKE_URL
  end

  # --- open-redirect guard -----------------------------------------------------
  # The session is encrypted, so the only way a poisoned value can be tested
  # end to end is through the sanitizer every stored value passes through.

  def safe(value)
    ClerkAuthenticatable.safe_return_path(value, fallback: "/dashboard")
  end

  test "absolute URLs fall back to the dashboard" do
    assert_equal "/dashboard", safe("https://evil.example")
    assert_equal "/dashboard", safe("http://evil.example/my-apps")
    assert_equal "/dashboard", safe("javascript:alert(1)")
  end

  test "protocol-relative and backslash variants fall back to the dashboard" do
    assert_equal "/dashboard", safe("//evil.example")
    assert_equal "/dashboard", safe("//evil.example/my-apps")
    assert_equal "/dashboard", safe("/\\evil.example")
    assert_equal "/dashboard", safe("\\\\evil.example")
  end

  test "non-strings, blanks, whitespace and relative paths fall back to the dashboard" do
    assert_equal "/dashboard", safe(nil)
    assert_equal "/dashboard", safe("")
    assert_equal "/dashboard", safe(" /my-apps")
    assert_equal "/dashboard", safe("/my-apps\n")
    assert_equal "/dashboard", safe("my-apps")
    assert_equal "/dashboard", safe(%w[/my-apps])
  end

  test "paths that would loop back to the auth pages fall back to the dashboard" do
    assert_equal "/dashboard", safe("/sign-in")
    assert_equal "/dashboard", safe("/sign-up")
  end

  test "plain same-origin paths are kept" do
    assert_equal "/", safe("/")
    assert_equal "/my-apps", safe("/my-apps")
    assert_equal "/my-apps/foo/compatibilities", safe("/my-apps/foo/compatibilities")
    assert_equal "/my-apps/foo/compatibilities?x=1", safe("/my-apps/foo/compatibilities?x=1")
  end
end
