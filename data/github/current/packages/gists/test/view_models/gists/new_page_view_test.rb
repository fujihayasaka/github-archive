# typed: true
# frozen_string_literal: true

require "test_helper"

class GistsNewPageViewTest < GitHub::TestCase
  setup do
    @view = Gists::NewPageView.new
  end

  test "public gist label is correct in each environment" do
    assert_equal "public", @view.public_gist_label
  end

  test "public gist description is correct in each environment" do
    expected_public_desc = "Public gists are visible to everyone."
    assert_equal expected_public_desc, @view.public_gist_description
  end
end
