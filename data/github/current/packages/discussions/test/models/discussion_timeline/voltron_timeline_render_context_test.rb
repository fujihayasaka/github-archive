# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::VoltronTimelineRenderContextTest < GitHub::TestCase
  fixtures do
    @repo_owner = create(:verified_user)
    @public_repo = create(:repository, owner: @repo_owner, has_discussions: true)
    @discussion = create(:discussion, repository: @public_repo)
  end

  context "#renderables" do
    test "splits comments into start, end and provides correct offset values for next split" do
      comments = [
        create(:discussion_comment, discussion: @discussion, created_at: 10.seconds.ago),
        create(:discussion_comment, discussion: @discussion, created_at: 5.seconds.ago),
        create(:discussion_comment, discussion: @discussion),
      ].each(&:reload)

      first_half_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 2,
        first_half: true
      )

      last_half_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 2,
        first_half: false
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

      assert_equal expected, first_half_render_context.renderables + last_half_render_context.renderables

      first_half_next_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        before_cursor: expected_hidden_items.before_cursor,
        after_cursor: expected_hidden_items.after_cursor,
        items_per_page: 2,
        first_half: true
      )

      last_half_next_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 2,
        before_cursor: expected_hidden_items.before_cursor,
        after_cursor: expected_hidden_items.after_cursor,
        first_half: false
      )

      expected = [
        comments.drop(1).take(1),
      ]

      assert_equal expected, first_half_next_render_context.renderables + last_half_next_render_context.renderables
    end

    test "inserts a new marker into the timeline" do
      comments = [
        create(:discussion_comment, discussion: @discussion, created_at: 5.days.ago),
        create(:discussion_comment, discussion: @discussion, created_at: 5.seconds.ago),
        create(:discussion_comment, discussion: @discussion),
      ]
      last_read_at = 1.day.ago
      @discussion.set_last_read_at_for(viewer: @repo_owner, time: last_read_at)

      first_half_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 10,
        first_half: true
      )

      last_half_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
        @discussion,
        viewer: @repo_owner,
        items_per_page: 10,
        first_half: false
      )

      expected = [
        :timeline_header,
        [comments.first],
        :new_marker,
        comments.last(2),
        :unread_marker,
      ]
      comments.map(&:reload)
      renderables = first_half_render_context.renderables + last_half_render_context.renderables

      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when the new marker is in the start items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(7.days.ago, [9, 8, 6], [5, 4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items[0..1],
        :new_marker,
        start_items[2..2],
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "does not insert a new marker into the timeline when you've never read anything" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(nil, [7, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "does not insert a new marker into the timeline when everything is new" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(8.days.ago, [7, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "does not insert a new marker into the timeline when nothing is new" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(Time.now, [7, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when last_read_at is in the middle of start items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(7.days.ago, [8, 6, 5], [4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items[0..0],
        :new_marker,
        start_items[1..2],
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when last_read_at is in the middle of end items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(3.days.ago, [8, 7, 6], [5], [4, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        hidden_items,
        end_items[0..0],
        :new_marker,
        end_items[1..2],
        :unread_marker,
      ]

      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when last_read_at is in the middle of hidden items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(5.days.ago, [9, 8, 7], [6, 4], [3, 2, 1])
      expected = [
        :timeline_header,
        start_items,
        :new_marker,
        hidden_items,
        end_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "does not insert a new marker into the timeline when hidden_items are empty and end items are empty and there are no unread items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(Time.now, [9, 8, 7], [], [])
      expected = [
        :timeline_header,
        start_items,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when hidden_items are empty and end items are empty and last read at is in start items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(8.days.ago, [9, 7, 6], [], [])
      expected = [
        :timeline_header,
        start_items[0..0],
        :new_marker,
        start_items[1..2],
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "inserts a new marker into the timeline when hidden_items are nil and end items are empty and it is at the end of start items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(7.days.ago, [9, 8, 6], [], [])
      expected = [
        :timeline_header,
        start_items[0..1],
        :new_marker,
        start_items[2..2],
        :unread_marker,
      ]
      assert_equal expected, renderables
    end

    test "does not insert a new marker into the timeline when there are no items" do
      start_items, end_items, hidden_items, renderables = timeline_items_for(7.days.ago, [], [], [])
      expected = [
        :timeline_header,
        :unread_marker,
      ]
      assert_equal expected, renderables
    end
  end

  context ".items_per_page" do
    test "uses default value if unset" do
      Discussions::Kv.store.del(DiscussionTimeline::ITEMS_PER_PAGE_KEY)

      default = DiscussionTimeline::DEFAULT_ITEMS_PER_PAGE
      render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(@discussion, viewer: @repo_owner, first_half: false)
      assert_equal default, render_context.items_per_page
    end

    test "uses default value if an error occurs" do
      Discussions::Kv.store.expects(:get).returns(GitHub::Result.new { raise RuntimeError.new("oh no") })

      default = DiscussionTimeline::DEFAULT_ITEMS_PER_PAGE
      render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(@discussion, viewer: @repo_owner, first_half: false)
      assert_equal default, render_context.items_per_page
    end

    test "uses the value from KV if one is present" do
      DiscussionTimeline::VoltronTimelineRenderContext.items_per_page = 10

      assert_equal 10, DiscussionTimeline::VoltronTimelineRenderContext.items_per_page

      render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(@discussion, viewer: @repo_owner, first_half: false)
      assert_equal 10, render_context.items_per_page
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

    hidden_marker = if hidden_items.any?
      DiscussionTimelineHiddenItems.new(hidden_items.size, before: end_items[0], after: start_items[-1])
    end

    @discussion.set_last_read_at_for(viewer: @repo_owner, time: last_read_at) if last_read_at

    # Update the items from the after commit (auto upvotes)
    [start_items, end_items].each { |items| items.each(&:reload) }

    first_half_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
      @discussion,
      viewer: @repo_owner,
      items_per_page: 6,
      first_half: true
    )

    last_half_render_context = DiscussionTimeline::VoltronTimelineRenderContext.new(
      @discussion,
      viewer: @repo_owner,
      items_per_page: 6,
      first_half: false
    )

    renderables = first_half_render_context.renderables + last_half_render_context.renderables

    regrouped_renderables = renderables.flatten.chunk_while { |i, j| j.is_a?(DiscussionComment) && i.is_a?(DiscussionComment) }.map do |chunk|
      first = chunk[0]
      first.is_a?(DiscussionComment) ? chunk : first
    end

    [start_items, end_items, hidden_marker, regrouped_renderables]
  end
end
