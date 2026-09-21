require "test_helper"

class PagesControllerTest < ActionDispatch::IntegrationTest
  test "the landing page renders" do
    get root_path

    assert_response :success
    assert_select "title", text: /theme\.watch/
    assert_select "form[data-controller=waitlist]", minimum: 1
    assert_select "a[href=?]", "#waitlist", minimum: 1
  end

  test "the landing page has no bare href=\"#\" links" do
    get root_path

    # In-page anchors like #features are fine (CLAUDE.md); a bare # is not.
    assert_select 'a[href="#"]', count: 0
  end

  test "the landing page mock carries no fabricated counts" do
    get root_path

    assert_includes response.body, "See all compatible apps"
    assert_no_match(/See all \d+ compatible apps/, response.body)
  end

  test "sign-in and sign-up render the Clerk mount points" do
    get sign_in_path
    assert_response :success
    assert_select "[data-clerk-mount-mount-value=sign-in]"

    get sign_up_path
    assert_response :success
    assert_select "[data-clerk-mount-mount-value=sign-up]"
  end

  test "the health check responds" do
    get "/up"

    assert_response :success
  end
end
