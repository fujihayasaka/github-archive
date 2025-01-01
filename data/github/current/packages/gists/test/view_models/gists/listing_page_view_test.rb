# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsListingPageViewTest < GitHub::TestCase
  setup do
    @view = Gists::ListingPageView.new \
      type: :public
  end

  test "type label is correct" do
    assert_equal "public", @view.type_label
  end
end
