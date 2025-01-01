# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::PaginatedRenderContextTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  context "#renderables" do
    test "splits comments into start, end and provides correct offset values for next split" do
      comments = [
        create(:discussion_comment, discussion: @discussion, created_at: 2.seconds.ago),
        create(:discussion_comment, discussion: @discussion, created_at: 1.second.ago),
        create(:discussion_comment, discussion: @discussion),
      ]

      render_context = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 2
      )

      after = comments[0]
      before = comments[2]
      expected_hidden_items = DiscussionTimelineHiddenItems.new(1, before: before, after: after)

      expected = [
        :timeline_header,
        comments.take(1),
        expected_hidden_items,
        comments.last(1),
        :unread_marker,
      ]

      assert_equal expected, render_context.renderables

      next_render_context = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        before_cursor: expected_hidden_items.before_cursor,
        after_cursor: expected_hidden_items.after_cursor,
        items_per_page: 2,
      )

      expected = [
        comments.drop(1).take(1),
        [],
      ]

      assert_equal expected, next_render_context.renderables
    end

    test "inserts a new marker into the timeline" do
      comments = [
        create(:discussion_comment, discussion: @discussion, created_at: 5.days.ago),
        create(:discussion_comment, discussion: @discussion, created_at: 1.hour.ago),
        create(:discussion_comment, discussion: @discussion),
      ]

      @discussion.set_last_read_at_for(viewer: @repo_owner, time: 1.day.ago)

      render_context = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 10,
      )

      expected = [
        :timeline_header,
        [comments.first],
        :new_marker,
        comments.last(2),
        :unread_marker,
      ]
      comments.map(&:reload)
      renderables = render_context.renderables

      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when the new marker is in the start items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(7.days.ago, [9, 8, 6], [5, 4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items[0..1],
        :new_marker,
        start_items[2..2],
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "does not insert a new marker into the timeline when you've never read anything" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(nil, [7, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "does not insert a new marker into the timeline when everything is new" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(8.days.ago, [7, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "does not insert a new marker into the timeline when nothing is new" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(Time.now, [7, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "inserts a new marker into the timeline when last_read_at is in the middle of start items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(7.days.ago, [8, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items[0..0],
        :new_marker,
        start_items[1..2],
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "inserts a new marker into the timeline when last_read_at is in the middle of end items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(3.days.ago, [8, 7, 6], [5], [4, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items[0..0],
        :new_marker,
        end_items[1..2],
        :unread_marker,
      ]

      assert_equal expected, render_context.renderables
    end

    test "inserts a new marker into the timeline when last_read_at is in the middle of hidden items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(5.days.ago, [9, 8, 7], [6, 4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        :new_marker,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "does not insert a new marker into the timeline when hidden_items are empty and end items are empty and there are no unread items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(Time.now, [9, 8, 7], [], [])
      expected = [
        :timeline_header,
        start_items,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "inserts a new marker into the timeline when hidden_items are empty and end items are empty and last read at is in start items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(8.days.ago, [9, 7, 6], [], [])
      expected = [
        :timeline_header,
        start_items[0..0],
        :new_marker,
        start_items[1..2],
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "inserts a new marker into the timeline when hidden_items are nil and end items are empty and it is at the end of start items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(7.days.ago, [9, 8, 6], [], [])
      expected = [
        :timeline_header,
        start_items[0..1],
        :new_marker,
        start_items[2..2],
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "does not insert a new marker into the timeline when there are no items" do
      start_items, end_items, hidden_items, render_context = timeline_items_for(7.days.ago, [], [], [])
      expected = [
        :timeline_header,
        :unread_marker,
      ]
      assert_equal expected, render_context.renderables
    end

    test "sends statistics to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 2
      ).renderables

      assert_equal 2, GitHub.dogstats.distributions("discussion_timeline.paginated_render_context.dist").length
    end
  end

  context "#reply_threads_by_parent_id" do
    test "includes a particular nested comment if it is marked as the answer" do
      comments = create_discussion_comments_with_time_between(5, @discussion)
      parent_comment_of_answer = comments[2]
      replies = create_list(:discussion_comment,
        DiscussionTimeline::DEFAULT_INITIAL_REPLY_COUNT + 5,
        discussion: @discussion,
        parent_comment: parent_comment_of_answer,
      )
      answer = replies[1]
      @discussion.chosen_comment = replies[1]

      render_context = DiscussionTimeline::PaginatedRenderContext.new(@discussion, viewer: @repo_owner)

      threads = render_context.reply_threads_by_parent_id
      thread = threads[parent_comment_of_answer.id]
      assert_includes thread.replies, answer
      assert_equal parent_comment_of_answer, thread.parent
    end
  end

  context ".items_per_page" do
    test "uses default value if unset" do
      Discussions::Kv.store.del(DiscussionTimeline::ITEMS_PER_PAGE_KEY)

      default = DiscussionTimeline::DEFAULT_ITEMS_PER_PAGE
      render_context = DiscussionTimeline::PaginatedRenderContext.new(@discussion, viewer: @repo_owner)
      assert_equal default, render_context.items_per_page
    end

    test "uses default value if an error occurs" do
      Discussions::Kv.store.expects(:get).returns(GitHub::Result.new { raise RuntimeError.new("oh no") })

      default = DiscussionTimeline::DEFAULT_ITEMS_PER_PAGE
      render_context = DiscussionTimeline::PaginatedRenderContext.new(@discussion, viewer: @repo_owner)
      assert_equal default, render_context.items_per_page
    end

    test "uses the value from KV if one is present" do
      DiscussionTimeline::PaginatedRenderContext.items_per_page = 10

      assert_equal 10, DiscussionTimeline::PaginatedRenderContext.items_per_page

      render_context = DiscussionTimeline::PaginatedRenderContext.new(@discussion, viewer: @repo_owner)
      assert_equal 10, render_context.items_per_page
    end
  end

  context "#start_items_for" do
    test "returns start_items from items list" do
      comments = create_list(:discussion_comment, 10, discussion: @discussion)

      start_items = DiscussionTimeline::PaginatedRenderContext.start_items_for(items: comments, items_per_page: 5)

      assert_equal comments.take(2), start_items
    end
  end

  context "#end_items_for" do
    test "returns end_items from items list" do
      comments = create_list(:discussion_comment, 10, discussion: @discussion)

      end_items = DiscussionTimeline::PaginatedRenderContext.end_items_for(items: comments, items_per_page: 5)

      assert_equal comments.last(3), end_items
    end
  end

  context "#timeline_items" do
    test "sends statistics to datadog" do
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)

      DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 2
      ).timeline_items

      assert_equal 2, GitHub.dogstats.distributions("discussion_timeline.paginated_render_context.dist").length
    end
  end

  context "#timeline_items_for_discussion" do
    test "includes comments, events, and event groups" do
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

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [event, comment, event_group], results
    end

    test "excludes events when include_events is set to false" do
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

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        include_events: false,
      ).timeline_items_for_discussion

      assert_equal [comment], results
    end

    test "excludes event from spammy user" do
      comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion) }

      event.actor.mark_as_spammy

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [comment], results
    end if GitHub.spamminess_check_enabled?

    test "includes created issue event" do
      @discussion.repository.update!(has_issues: true)
      comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      created_issue_event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion, event_type: :created_issue) }

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [created_issue_event, comment], results
    end

    test "excludes created issue event when issues are disabled" do
      @discussion.repository.update!(has_issues: false)
      comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      created_issue_event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion, event_type: :created_issue) }


      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [comment], results
    end

    test "excludes comment from spammy user" do
      comment0 = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      comment1 = Timecop.freeze(1.hour.ago) { create(:discussion_comment, discussion: @discussion) }
      perform_enqueued_jobs(only: [UpdateTableUserHiddenJob]) { comment0.user.mark_as_spammy }

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [comment1], results
    end if GitHub.spamminess_check_enabled?

    test "excludes event from user blocked by the viewer" do
      comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      event = Timecop.freeze(1.hour.ago) { create(:discussion_event, discussion: @discussion) }

      @repo_owner.block(event.actor)

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [comment], results
    end

    test "excludes nested comments" do
      comment = Timecop.freeze(50.minutes.ago) { create(:discussion_comment, discussion: @discussion) }
      nested_comment = create(:discussion_comment, parent_comment: comment, discussion: @discussion)

      results = DiscussionTimeline::PaginatedRenderContext.new(
        @discussion,
        viewer: @repo_owner,
      ).timeline_items_for_discussion

      assert_equal [comment], results
    end
  end

  def timeline_items_for(last_read_at, start_days, hidden_days, end_days)
    start_items = start_days.map do |days_ago|
      create(:discussion_comment, discussion: @discussion, created_at: days_ago.days.ago)
    end

    hidden_items = hidden_days.map do |days_ago|
      create(:discussion_comment, discussion: @discussion, created_at: days_ago.days.ago)
    end

    end_items = end_days.map do |days_ago|
      create(:discussion_comment, discussion: @discussion, created_at: days_ago.days.ago)
    end

    @discussion.set_last_read_at_for(viewer: @repo_owner, time: last_read_at) if last_read_at

    hidden_marker = if hidden_items.any?
      DiscussionTimelineHiddenItems.new(hidden_items.size, before: end_items[0], after: start_items[-1])
    end

    # Update the items from the after commit (auto upvotes)
    [start_items, end_items].each { |items| items.each(&:reload) }

    render_context = DiscussionTimeline::PaginatedRenderContext.new(
      @discussion,
      viewer: @repo_owner,
      items_per_page: 6,
    )

    [start_items, end_items, hidden_marker, render_context]
  end

  def create_discussion_comments_with_time_between(count, discussion)
    count.downto(1).map do |i|
      create(:discussion_comment, discussion: discussion, created_at: i.minutes.ago)
    end
  end
end
