require "test_helper"

class MyAppCompatibilitiesControllerTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  SLUG = "loox".freeze

  def compat_row(theme_title: "Dawn", status: "supported", visible: true, author: "developer", notes: nil)
    {
      app_listing_slug: SLUG, theme_title: theme_title, status: status, notes: notes,
      min_theme_version: nil, visible_publicly: visible, last_authored_by: author,
      updated_at: "2026-09-21T12:00:00Z", updated_by_app_developer_id: 1,
    }
  end

  def stub_index(*rows)
    stub_request(:get, shopinfo_url("/apps/#{SLUG}/compatibilities"))
      .to_return(json_response(200, { data: rows, pagination: { next_cursor: nil, has_more: false } }))
  end

  def put_url(theme_title)
    shopinfo_url("/apps/#{SLUG}/compatibilities/#{ERB::Util.url_encode(theme_title)}")
  end

  # --- index -------------------------------------------------------------------

  test "lists compatibility rows with an edit form each" do
    clerk_sign_in
    stub_index(compat_row, compat_row(theme_title: "Sense", status: "needs_customization", visible: false, author: "admin"))

    get my_app_compatibilities_path(SLUG)

    assert_response :success
    assert_select "h1", text: SLUG
    assert_select "li h3", text: "Dawn"
    assert_select "li h3", text: "Sense"
    assert_select "form[action=?]", my_app_compatibility_path(SLUG, "Dawn")
    assert_select "form[action=?]", my_app_compatibility_path(SLUG, "Sense")
    assert_select "li span", text: "Private", count: 1
    assert_includes response.body, "Last edited by admin"
  end

  test "both status selects use the single Compatibility vocabulary" do
    clerk_sign_in
    stub_index(compat_row(status: "needs_customization"))

    get my_app_compatibilities_path(SLUG)

    assert_select "select[name=status]", count: 2
    assert_select "select[name=status]" do |selects|
      selects.each do |select|
        values = select.css("option").map { |o| o["value"] }
        assert_equal Compatibility::STATUSES.keys, values
        labels = select.css("option").map(&:text)
        assert_equal Compatibility::STATUSES.values, labels
      end
    end
    assert_select "li select[name=status] option[selected][value=needs_customization]"
  end

  test "updated_at renders as relative time with the ISO timestamp preserved" do
    clerk_sign_in
    stub_index(compat_row.merge(updated_at: 3.days.ago.utc.iso8601))

    get my_app_compatibilities_path(SLUG)

    assert_select "li time[datetime]", text: "3 days ago"
    assert_select "li time[datetime]" do |times|
      assert_nothing_raised { Time.iso8601(times.first["datetime"]) }
    end
  end

  test "an unparseable updated_at falls back to the raw string" do
    clerk_sign_in
    stub_index(compat_row.merge(updated_at: "not a date"))

    get my_app_compatibilities_path(SLUG)

    assert_response :success
    assert_includes response.body, "not a date"
  end

  test "shows the empty state and the add form when there are no rows" do
    clerk_sign_in
    stub_index

    get my_app_compatibilities_path(SLUG)

    assert_response :success
    assert_select "h3", text: "No compatibility rows yet."
    assert_select "form[action=?]", my_app_compatibilities_path(SLUG)
    assert_select "main li", count: 0
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

  # --- create ------------------------------------------------------------------

  test "create PUTs the row to shopinfo.app with a boolean visibility and redirects with a notice" do
    clerk_sign_in
    put_stub = stub_request(:put, put_url("Dawn"))
      .with(body: { "status" => "supported", "notes" => "Works on 9.0+", "min_theme_version" => "9.0", "visible_publicly" => true })
      .to_return(json_response(201, compat_row(notes: "Works on 9.0+")))
    stub_index(compat_row(notes: "Works on 9.0+"))

    post my_app_compatibilities_path(SLUG), params: {
      theme_title: "  Dawn  ", status: "supported", notes: "Works on 9.0+", min_theme_version: "9.0", visible_publicly: "true",
    }

    assert_requested put_stub
    assert_redirected_to my_app_compatibilities_path(SLUG)
    follow_redirect!
    assert_select "[role=status]", text: "Compatibility saved."
    assert_select "li h3", text: "Dawn"
  end

  test "create with a blank theme title redirects with a flash that the layout renders" do
    clerk_sign_in
    stub_index

    post my_app_compatibilities_path(SLUG), params: { theme_title: "   ", status: "supported" }

    assert_redirected_to my_app_compatibilities_path(SLUG)
    follow_redirect!
    assert_response :success
    assert_select "[role=alert]", text: /Theme title is required\./
    assert_not_requested :put, %r{/apps/#{SLUG}/compatibilities/}
  end

  # --- update ------------------------------------------------------------------

  test "update PUTs the changed fields and redirects with a notice" do
    clerk_sign_in
    put_stub = stub_request(:put, put_url("Dawn"))
      .with(body: { "status" => "not_supported", "notes" => "", "min_theme_version" => "", "visible_publicly" => false })
      .to_return(json_response(200, compat_row(status: "not_supported", visible: false)))
    stub_index(compat_row(status: "not_supported", visible: false))

    patch my_app_compatibility_path(SLUG, "Dawn"),
          params: { status: "not_supported", notes: "", min_theme_version: "", visible_publicly: "false" }

    assert_requested put_stub
    assert_redirected_to my_app_compatibilities_path(SLUG)
    follow_redirect!
    assert_select "[role=status]", text: "Compatibility saved."
  end

  test "update URL-encodes a theme title with spaces" do
    clerk_sign_in
    put_stub = stub_request(:put, put_url("Dawn 2.0")).to_return(json_response(200, compat_row(theme_title: "Dawn 2.0")))
    stub_index

    patch my_app_compatibility_path(SLUG, "Dawn 2.0"), params: { status: "supported" }

    assert_requested put_stub
  end

  test "an admin_locked 403 on update redirects back with the specific flash" do
    clerk_sign_in
    stub_index(compat_row(theme_title: "Sense", author: "admin"))
    stub_request(:put, put_url("Sense")).to_return(json_response(403, { error: "forbidden", reason: "admin_locked" }))

    patch my_app_compatibility_path(SLUG, "Sense"),
          params: { status: "not_supported" },
          headers: { "HTTP_REFERER" => my_app_compatibilities_url(SLUG) }

    assert_redirected_to my_app_compatibilities_url(SLUG)
    follow_redirect!
    assert_select "[role=alert]", text: /claim review window has closed/
  end

  test "a not_owner 403 on update redirects back with the ownership flash" do
    clerk_sign_in
    stub_index
    stub_request(:put, put_url("Dawn")).to_return(json_response(403, { error: "forbidden", reason: "not_owner" }))

    patch my_app_compatibility_path(SLUG, "Dawn"),
          params: { status: "supported" },
          headers: { "HTTP_REFERER" => my_app_compatibilities_url(SLUG) }

    follow_redirect!
    assert_select "[role=alert]", text: "You do not own this app listing."
  end

  test "a 422 on update redirects back with the validation flash" do
    clerk_sign_in
    stub_index
    stub_request(:put, put_url("Dawn")).to_return(json_response(422, { error: "validation_failed", details: { status: ["is not included in the list"] } }))

    patch my_app_compatibility_path(SLUG, "Dawn"),
          params: { status: "garbage" },
          headers: { "HTTP_REFERER" => my_app_compatibilities_url(SLUG) }

    follow_redirect!
    assert_select "[role=alert]", text: /did not accept that change/
  end

  test "redirects to sign-in when signed out" do
    get my_app_compatibilities_path(SLUG)

    assert_redirected_to sign_in_path
  end
end
