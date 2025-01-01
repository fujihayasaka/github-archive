# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/conditional_access/filter_test_helper"

class DiscussionTimeline::LiveUpdatesRenderContextTest < GitHub::TestCase
  include ConditionalAccess::FilterTestHelper

  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  context "#renderables" do
    test "returns passed in comment" do
      _old_comment = create(:discussion_comment, discussion: @discussion, created_at: 10.minutes.ago)
      new_comment = create(:discussion_comment, discussion: @discussion, created_at: 1.minute.ago)

      render_context = DiscussionTimeline::LiveUpdatesRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        timeline_last_rendered: 2.minutes.ago,
        cap_filter: cap_authorizing_filter([@discussion])
      )

      expected = [
        :unread_marker, [new_comment]
      ]

      assert_equal expected, render_context.renderables
    end
  end

  context "#timeline_items" do
    test "returns only items newer than last timeline render" do
      _old_comment = create(:discussion_comment, discussion: @discussion, created_at: 10.minutes.ago)
      new_comment = create(:discussion_comment, discussion: @discussion, created_at: 1.minute.ago)

      render_context = DiscussionTimeline::LiveUpdatesRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        timeline_last_rendered: 2.minutes.ago,
        cap_filter: cap_authorizing_filter([@discussion])
      )

      assert_equal [new_comment], render_context.timeline_items
    end
  end
end
