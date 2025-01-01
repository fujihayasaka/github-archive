# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionSpotlightPositionerTest < GitHub::TestCase
  fixtures do
    @repository = create(:repository, has_discussions: true)
    @spotlight1 = create(:discussion_spotlight, repository: @repository, position: 1)
    @spotlight2 = create(:discussion_spotlight, repository: @repository, position: 2)
  end

  context ".reposition!" do
    test "sets spotlight positions based on their position in the array" do
      DiscussionSpotlightPositioner.reposition!(@repository, [@spotlight2.id, @spotlight1.id])

      assert_equal 2, @spotlight1.reload.position
      assert_equal 1, @spotlight2.reload.position
    end

    test "does not set spotlight positions for spotlights not in the same repository" do
      other_spotlight = create(:discussion_spotlight, position: 5)

      DiscussionSpotlightPositioner.reposition!(@repository, [other_spotlight.id, @spotlight2.id, @spotlight1.id])

      assert_equal 5, other_spotlight.reload.position
    end
  end
end
