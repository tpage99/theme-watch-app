require "test_helper"

class MyAppsControllerTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  setup do
    @log = StringIO.new
    @log_sink = ActiveSupport::Logger.new(@log)
    Rails.logger.broadcast_to(@log_sink)
  end

  teardown do
    Rails.logger.stop_broadcasting_to(@log_sink)
  end

  test "a 503 from shopinfo.app shows a plain message and logs the detail" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/me/apps"))
      .to_return(json_response(503, { error: "internal_error", message: "deploy in progress" }))

    get my_apps_path

    assert_response :bad_gateway
    assert_includes response.body, ApplicationController::UPSTREAM_UNAVAILABLE
    assert_includes response.body, "Could not load your apps."
    refute_includes response.body, "HTTP 503"
    refute_includes response.body, "web_scraper"
    refute_includes response.body, "deploy in progress"

    logged = @log.string
    assert_includes logged, "[ShopinfoApi]"
    assert_includes logged, "status=503"
    assert_includes logged, "deploy in progress"
    assert_includes logged, "base_url=\"#{SHOPINFO_BASE_URL}/\""
    assert_match(/request_id="[^"]+"/, logged)
  end

  test "a connection failure shows the same plain message" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/me/apps")).to_raise(Faraday::ConnectionFailed.new("connection refused"))

    get my_apps_path

    assert_response :bad_gateway
    assert_includes response.body, ApplicationController::UPSTREAM_UNAVAILABLE
    refute_includes response.body, "connection refused"
    assert_includes @log.string, "Faraday::ConnectionFailed"
  end

  test "a 401 from shopinfo.app tells the user to sign in again and logs the config hint" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/me/apps")).to_return(json_response(401, { error: "unauthorized", reason: "invalid_token" }))

    get my_apps_path

    assert_response :bad_gateway
    assert_includes response.body, "Sign out, sign back in, and try again."
    refute_includes response.body, "Clerk instance"
    assert_includes @log.string, "CLERK_FRONTEND_API"
  end

  test "the signed-out user is redirected to sign-in before any API call" do
    get my_apps_path

    assert_redirected_to sign_in_path
    assert_not_requested :get, shopinfo_url("/me/apps")
  end
end
