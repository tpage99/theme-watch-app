require "test_helper"

class DashboardControllerTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  def ping_body(email: "dev@example.com")
    {
      clerk_user_id: "user_test", app_developer_id: 7, email: email, name: nil,
      linked_user_id: nil, clerk_last_seen_at: "2026-09-21T12:00:00Z",
    }
  end

  test "renders the developer profile from /me/ping" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/me/ping")).to_return(json_response(200, ping_body))

    get dashboard_path

    assert_response :success
    assert_select "h2", text: /Hello, dev@example\.com\./
    assert_select "dd", text: "user_test"
    assert_select "dd", text: "7"
  end

  test "falls back to a generic greeting when shopinfo.app has no email yet" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/me/ping")).to_return(json_response(200, ping_body(email: nil)))

    get dashboard_path

    assert_response :success
    assert_select "h2", text: /Hello, developer\./
  end

  test "uses the email claim from the Clerk token when shopinfo.app has none" do
    clerk_sign_in(email: "claim@example.com")
    stub_request(:get, shopinfo_url("/me/ping")).to_return(json_response(200, ping_body(email: nil)))

    get dashboard_path

    assert_select "h2", text: /Hello, claim@example\.com\./
  end

  test "a timeout from shopinfo.app shows the plain message instead of the profile" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/me/ping")).to_timeout

    get dashboard_path

    assert_response :bad_gateway
    assert_select "[role=alert]", text: /shopinfo\.app is not responding right now/
    assert_select "dl", count: 0
  end

  test "redirects to sign-in when signed out" do
    get dashboard_path

    assert_redirected_to sign_in_path
  end
end
