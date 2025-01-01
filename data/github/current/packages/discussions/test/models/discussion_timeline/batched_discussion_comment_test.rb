# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::BatchedDiscussionCommentTest < GitHub::TestCase
  INITIAL_COUNT = 3

  fixtures do
    @viewer = create(:verified_user)
    @public_repo = create(:repository, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  context "#load" do
    test "returns all top level comments" do
      comments = create_list(:discussion_comment, 6, discussion: @discussion)
      results = DiscussionTimeline::BatchedDiscussionComment.load(
        @discussion, @viewer,
        initial_count: INITIAL_COUNT
      )

      comments.each(&:reload)

      assert_equal comments, results.map(&:first)
    end

    test "only returns comments and replies that will be rendered" do
      comments = create_list(:discussion_comment, 6, discussion: @discussion)
      replies_1 = create_list(:discussion_comment, 5, discussion: @discussion, parent_comment: comments.first)
      replies_2 = create_list(:discussion_comment, 5, discussion: @discussion, parent_comment: comments.last)
      results = DiscussionTimeline::BatchedDiscussionComment.load(
        @discussion, @viewer,
        items_per_page: 2,
        initial_count: INITIAL_COUNT
      )

      comments.each(&:reload)
      replies_1.each(&:reload)
      replies_2.each(&:reload)

      expected = comments + replies_1.last(INITIAL_COUNT) + replies_2.last(INITIAL_COUNT)

      assert_equal expected, results.map(&:first)
    end
  end
end
