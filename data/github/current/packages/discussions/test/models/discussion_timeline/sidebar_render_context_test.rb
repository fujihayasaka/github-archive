# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::SidebarRenderContextTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  context "#events" do
    test "includes events and event groups" do
      comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion) }
      group_event1 = Timecop.freeze(40.minutes.ago) do
        create(:discussion_event, discussion: @discussion, comment: comment, event_type: "answer_marked")
      end
      group_event2 = Timecop.freeze(30.minutes.ago) do
        create(:discussion_event, discussion: @discussion, comment: comment, actor: group_event1.actor,
          event_type: "answer_unmarked")
      end
      event_group = DiscussionEventGroup.new([group_event1, group_event2])

      results = DiscussionTimeline::SidebarRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).events

      assert_equal [event_group, event], results
    end

    test "orders events by newest first" do
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, :reopened, discussion: @discussion) }
      other_event = Timecop.freeze(1.day.ago) { create(:discussion_event, :closed, discussion: @discussion) }


      results = DiscussionTimeline::SidebarRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).events

      assert_equal [event, other_event], results
    end

    test "excludes event from spammy user" do
      Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion) }

      event.actor.mark_as_spammy

      results = DiscussionTimeline::SidebarRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).events

      assert_equal [], results
    end if GitHub.spamminess_check_enabled?

    test "includes created issue event" do
      @discussion.repository.update!(has_issues: true)
      created_issue_event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion, event_type: :created_issue) }

      results = DiscussionTimeline::SidebarRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).events

      assert_equal [created_issue_event], results
    end

    test "excludes created issue event when issues are disabled" do
      @discussion.repository.update!(has_issues: false)
      created_issue_event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion, event_type: :created_issue) }

      results = DiscussionTimeline::SidebarRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).events

      assert_equal [], results
    end

    test "excludes event from user blocked by the viewer" do
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion) }

      @repo_owner.block(event.actor)

      results = DiscussionTimeline::SidebarRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).events

      assert_equal [], results
    end
  end
end
