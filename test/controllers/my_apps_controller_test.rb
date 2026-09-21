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

  def listing(slug: "loox", name: "Loox", visible: true, verified: false, count: 3)
    {
      slug: slug, name: name, description: "Photo reviews", category: "reviews_ugc",
      category_label: "Reviews & UGC", icon_url: nil, shopify_app_store_url: "https://apps.shopify.com/#{slug}",
      app_store_rating: nil, app_store_install_count_band: nil, support_url: nil, docs_url: nil,
      claimed: true, verified: verified, visible_publicly: visible, compatible_theme_count: count,
      claim_review_window_closes_at: nil, created_at: "2026-09-01T00:00:00Z", updated_at: "2026-09-01T00:00:00Z",
    }
  end

  def stub_apps(*listings)
    stub_request(:get, shopinfo_url("/me/apps"))
      .to_return(json_response(200, { data: listings, pagination: { next_cursor: nil, has_more: false } }))
  end

  # --- happy path and empty state -------------------------------------------

  test "lists claimed apps with a manage link per card" do
    clerk_sign_in
    stub_apps(listing, listing(slug: "klaviyo", name: "Klaviyo", visible: false, count: 1))

    get my_apps_path

    assert_response :success
    assert_select "li h2", text: "Loox"
    assert_select "li h2", text: "Klaviyo"
    assert_select "a[href=?]", my_app_compatibilities_path("loox"), text: /Manage compatibilities/
    assert_select "a[href=?]", my_app_compatibilities_path("klaviyo")
    assert_select "span", text: "Private", count: 1
    assert_includes response.body, "3 compatible themes"
    assert_includes response.body, "1 compatible theme"
  end

  test "shows the empty state when nothing is claimed" do
    clerk_sign_in
    stub_apps

    get my_apps_path

    assert_response :success
    assert_select "h3", text: "No claimed apps yet."
    assert_select "main li", count: 0
  end

  # --- failures --------------------------------------------------------------

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
