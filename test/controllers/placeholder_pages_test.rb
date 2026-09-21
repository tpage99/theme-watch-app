require "test_helper"

class PlaceholderPagesTest < ActionDispatch::IntegrationTest
  include ClerkSessionTestHelper

  test "alerts says it is coming in Phase 3" do
    clerk_sign_in
    get alerts_path

    assert_response :success
    assert_select "header p", text: "Coming in Phase 3"
  end

  test "settings says it is coming in Phase 3" do
    clerk_sign_in
    get settings_path

    assert_response :success
    assert_select "header p", text: "Coming in Phase 3"
    refute_includes response.body, "Phase 2"
  end

  test "sidebar links and the sign-out button carry a visible focus ring" do
    clerk_sign_in
    get alerts_path

    assert_select "aside nav a", minimum: 4 do |links|
      links.each { |a| assert_includes a["class"], "focus-visible:ring-2", "nav link without focus ring: #{a.text.strip}" }
    end
    assert_select "aside button", text: /Sign out/ do |buttons|
      assert_includes buttons.first["class"], "focus-visible:ring-2"
    end
  end
end
