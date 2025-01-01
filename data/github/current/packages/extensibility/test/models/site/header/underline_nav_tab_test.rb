# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Header::UnderlineNavTabTest < GitHub::TestCase
  setup do
    @raw_tab = {
      text: "Label",
      href: "https://github.com",
      icon: "squirrel",
      highlight: [:code],
      data: { hotkey: "g p" },
      count: 4
    }
  end

  test "attributes are initialized" do
    tab = Site::Header::UnderlineNavTab.new(**@raw_tab)

    assert_equal tab.text, @raw_tab[:text]
    assert_equal tab.href, @raw_tab[:href]
    assert_equal tab.icon, @raw_tab[:icon]
    assert_equal tab.highlight, @raw_tab[:highlight]
    assert_equal tab.data, @raw_tab[:data]
    assert_equal tab.count, @raw_tab[:count]
  end

  test "count supports lambda value" do
    tab = Site::Header::UnderlineNavTab.new(**@raw_tab.merge(count: ->() { 2 }))

    assert_equal tab.count.call, 2
  end
end
