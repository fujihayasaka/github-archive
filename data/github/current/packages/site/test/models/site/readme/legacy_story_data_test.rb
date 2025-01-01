# typed: true
# frozen_string_literal: true

require "test_helper"

class Site::Readme::LegacyStoryDataTest < GitHub::TestCase
  test "storydata count" do
    assert_equal 61, Site::Readme::LegacyStoryData::DATA.count
  end

  test "category and slug are present" do
    Site::Readme::LegacyStoryData::DATA.each do |story|
      assert story[:category].present?
      assert story[:slug].present?
    end
  end
end
