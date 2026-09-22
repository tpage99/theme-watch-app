require "test_helper"

class ApplicationHelperTest < ActionView::TestCase
  test "button_classes always includes a visible focus ring" do
    ApplicationHelper::BUTTON_VARIANTS.each_key do |variant|
      classes = button_classes(variant)
      assert_includes classes, "focus-visible:ring-2"
      assert_includes classes, "focus-visible:ring-tw-400"
    end
    assert_includes button_classes(:primary, "w-full"), "w-full"
  end

  test "button_classes rejects unknown variants" do
    assert_raises(KeyError) { button_classes(:nope) }
  end

  test "relative_time wraps the value in a time element with the ISO datetime" do
    html = relative_time(2.hours.ago.utc.iso8601)

    assert_dom_equal html, html # well-formed
    assert_match(/<time datetime="\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z" title="[^"]+">about 2 hours ago<\/time>/, html)
  end

  test "relative_time is blank for blank input and raw for unparseable input" do
    assert_equal "", relative_time(nil)
    assert_equal "", relative_time("")
    assert_equal "garbage", relative_time("garbage")
  end
end
