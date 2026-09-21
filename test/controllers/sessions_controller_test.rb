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
