require "test_helper"

class CompatibilityTest < ActiveSupport::TestCase
  test "the status vocabulary matches the shopinfo.app contract" do
    assert_equal %w[supported needs_customization not_supported unknown], Compatibility::STATUSES.keys
  end

  test "status_options is in [label, value] order for select helpers" do
    assert_equal ["Supported", "supported"], Compatibility.status_options.first
    assert_equal Compatibility::STATUSES.size, Compatibility.status_options.size
  end

  test "status_label humanizes unknown values instead of raising" do
    assert_equal "Needs customization", Compatibility.status_label("needs_customization")
    assert_equal "Something new", Compatibility.status_label("something_new")
  end
end
