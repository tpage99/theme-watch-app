require "test_helper"

class MyAppCompatibilitiesControllerTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  SLUG = "loox".freeze

  def compat_row(theme_title: "Dawn", status: "supported", visible: true, author: "developer")
    {
      app_listing_slug: SLUG, theme_title: theme_title, status: status, notes: nil,
      min_theme_version: nil, visible_publicly: visible, last_authored_by: author,
      updated_at: "2026-09-21T12:00:00Z", updated_by_app_developer_id: 1,
    }
  end

  test "a blank theme title redirects with a flash that the layout renders" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/apps/#{SLUG}/compatibilities"))
      .to_return(json_response(200, { data: [], pagination: { next_cursor: nil, has_more: false } }))

    post my_app_compatibilities_path(SLUG), params: { theme_title: "   ", status: "supported" }

    assert_redirected_to my_app_compatibilities_path(SLUG)
    follow_redirect!
    assert_response :success
    assert_select "[role=alert]", text: /Theme title is required\./
    assert_not_requested :put, %r{/apps/#{SLUG}/compatibilities/}
  end

  test "an admin_locked 403 on update redirects back with the specific flash" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/apps/#{SLUG}/compatibilities"))
      .to_return(json_response(200, { data: [compat_row(theme_title: "Sense", author: "admin")], pagination: { next_cursor: nil, has_more: false } }))
    stub_request(:put, shopinfo_url("/apps/#{SLUG}/compatibilities/Sense"))
      .to_return(json_response(403, { error: "forbidden", reason: "admin_locked" }))

    patch my_app_compatibility_path(SLUG, "Sense"),
          params: { status: "not_supported" },
          headers: { "HTTP_REFERER" => my_app_compatibilities_url(SLUG) }

    assert_redirected_to my_app_compatibilities_url(SLUG)
    follow_redirect!
    assert_select "[role=alert]", text: /claim review window has closed/
  end

  test "a 404 listing on index shows the not-found message" do
    clerk_sign_in
    stub_request(:get, shopinfo_url("/apps/#{SLUG}/compatibilities"))
      .to_return(json_response(404, { error: "not_found" }))

    get my_app_compatibilities_path(SLUG)

    assert_response :not_found
    assert_includes response.body, "That app listing was not found on shopinfo.app."
    assert_includes response.body, "Could not load compatibilities."
  end
end
