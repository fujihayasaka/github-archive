# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class DiscussionTimeline::PermalinkRenderContextTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  setup do
    DiscussionTimeline::PaginatedRenderContext.items_per_page = 2
  end

  context "#renderables" do
    test "renders hidden items when comment is not found" do
      comments = create_discussion_comments_with_time_between(5, @discussion)
      before = DiscussionTimelineHiddenItems.to_cursor(comments[4])
      after = DiscussionTimelineHiddenItems.to_cursor(comments[0])

      anchor = DiscussionTimeline::PermalinkRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        before_cursor: before,
        after_cursor: after,
        permalink_comment: nil,
        anchor_id: 0,
        cap_filter: cap_authorizing_filter([@discussion])
      )

      expected = [
        DiscussionTimelineHiddenItems.new(3, before: before, after: after)
      ]
      assert_equal expected, anchor.renderables
    end

    test "renders permalinked comment when comment is found" do
      comments = create_discussion_comments_with_time_between(5, @discussion)
      before = DiscussionTimelineHiddenItems.to_cursor(comments[4])
      after = DiscussionTimelineHiddenItems.to_cursor(comments[0])
      permalinked_comment = comments[2]

      anchor = DiscussionTimeline::PermalinkRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        before_cursor: before,
        after_cursor: after,
        permalink_comment: permalinked_comment,
        anchor_id: permalinked_comment.id,
        cap_filter: cap_authorizing_filter([@discussion])
      )

      expected = [
        DiscussionTimelineHiddenItems.new(1, before: permalinked_comment, after: after),
        [permalinked_comment],
        DiscussionTimelineHiddenItems.new(1, before: before, after: permalinked_comment),
      ]

      assert_equal expected, anchor.renderables
    end

    test "includes context before and after a permalinked reply" do
      comments = create_discussion_comments_with_time_between(5, @discussion)
      before = DiscussionTimelineHiddenItems.to_cursor(comments[4])
      after = DiscussionTimelineHiddenItems.to_cursor(comments[0])
      permalinked_comment = comments[2]
      replies = create_list(:discussion_comment,
        DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT + 5,
        discussion: @discussion,
        parent_comment: permalinked_comment,
      )
      anchor_id = replies[5].id

      render_context = DiscussionTimeline::PermalinkRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        before_cursor: before,
        after_cursor: after,
        permalink_comment: permalinked_comment,
        anchor_id: anchor_id,
        cap_filter: cap_authorizing_filter([@discussion])
      )

      expected = [
        DiscussionTimelineHiddenItems.new(1, before: permalinked_comment, after: after),
        [permalinked_comment],
        DiscussionTimelineHiddenItems.new(1, before: before, after: permalinked_comment),
      ]
      assert_equal expected, render_context.renderables

      threads = render_context.reply_threads_by_parent_id
      thread = threads[permalinked_comment.id]
      assert_equal permalinked_comment, thread.parent
      assert_equal replies.last(DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT + 3), thread.replies
    end
  end

  # Creates comments with some time in between. This is important for the tests in this suite, since the cursor
  # logic used to sort discussion comments orders primarily by created_at (see
  # app/models/discussion_timeline/render_context.rb#timeline_items_for_discussion).
  def create_discussion_comments_with_time_between(count, discussion)
    count.downto(1).map do |i|
      create(:discussion_comment, discussion: discussion, created_at: i.minutes.ago)
    end
  end
end
