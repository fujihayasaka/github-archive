# typed: true
# frozen_string_literal: true

require "test_helper"

class TabTest < GitHub::TestCase
  include BackgroundDeletesTestHelpers

  fixtures do
    @repo = create(:repository)
    @tab  = create(:tab, anchor: "GitHub",
                    url: "https://github.com",
                    repository: @repo)
  end

  test "knows its repository" do
    assert_equal @repo, @tab.repository
  end

  test "is deleted with repository" do
    other_repository = create :repository
    other_tab = create(:tab)

    assert_destroyed_in_background_with_parent do |config|
      config.parent_record = @repo
      config.expect_destroyed = [@tab]
      config.expect_not_destroyed = [other_tab]
    end
  end
end
