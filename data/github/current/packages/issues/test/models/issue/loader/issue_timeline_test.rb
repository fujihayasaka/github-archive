# typed: true
# frozen_string_literal: true

require "test_helper"

class IssueTimelineLoaderTest < GitHub::TestCase
  setup do
    @issue = create(:issue)

    10.times do |n|
      label = create(:label, repository: @issue.repository, name: "label #{n}", color: "ff0000")
      @issue.events.create!(actor: @issue.user, event: "labeled", label: label, created_at: n.days.ago)
    end

    @context = Issue::Adapter::Context.new(
      @issue,
      @issue.repository,
      @issue.repository.owner
    )

    @ordered_issue_events = @issue.events.unscope(:order).order(:created_at)
  end

  def get_cursor(issue_event)
    placeholder = ::Timeline::Placeholder::IssueEvent.new(
      id: issue_event.id,
      sort_datetimes: [issue_event.created_at],
      event_name: issue_event.event,
    )
    Platform::ConnectionWrappers::CursorGenerator.generate_cursor(placeholder.cursor_key, version: :v2)
  end

  context "#since" do
    test "returns all entries if no 'since' value specified" do
      loader = Issue::Loader::IssueTimeline.new(@context, {})
      assert_equal 10, loader.timeline_start.async_filtered_count.sync
    end

    test "returns all entries after 'since' value if one is specified" do
      timeline_since = @ordered_issue_events.second.created_at + 1.minute

      loader = Issue::Loader::IssueTimeline.new(@context, { timeline_since: timeline_since })
      assert_equal 8, loader.timeline_start.async_filtered_count.sync
    end
  end

  context "pagination" do
    test "returns all entries if no after_cursor or before_cursor value specified" do
      loader = Issue::Loader::IssueTimeline.new(@context, {})
      assert_equal 10, loader.timeline_start.async_filtered_count.sync
    end

    test "returns all entries after after_cursor value if one is specified" do
      after_cursor = get_cursor(@ordered_issue_events.third)

      loader = Issue::Loader::IssueTimeline.new(@context, { after_cursor: after_cursor })
      remaining = @ordered_issue_events.drop(3)

      assert_equal 7, loader.timeline_start.async_filtered_count.sync
      assert_same_elements remaining, loader.timeline_start.async_entries.sync
    end

    test "returns all entries after before_cursor value if one is specified" do
      before_cursor = get_cursor(@ordered_issue_events.third)

      loader = Issue::Loader::IssueTimeline.new(@context, { before_cursor: before_cursor })
      remaining = @ordered_issue_events.take(2)

      assert_equal 2, loader.timeline_start.async_entries.sync.count
      assert_same_elements remaining, loader.timeline_start.async_entries.sync
    end

    test "returns entries between after_cursor and before_cursor if both values specified" do
      after_cursor = get_cursor(@ordered_issue_events[2])
      before_cursor = get_cursor(@ordered_issue_events[6])

      loader = Issue::Loader::IssueTimeline.new(@context, { after_cursor: after_cursor, before_cursor: before_cursor })

      assert_equal 3, loader.timeline_start.async_entries.sync.count

      remaining = @ordered_issue_events.drop(3).take(3)
      assert_same_elements remaining, loader.timeline_start.async_entries.sync
    end
  end

  context "#focused_item" do
    test "returns nil if focused_item_global_id isn't specified" do
      loader = Issue::Loader::IssueTimeline.new(@context, {})
      assert_nil loader.focused_item
    end

    test "returns page for focused item if focused_item_global_id is specified" do
      focused_item = @ordered_issue_events.fifth
      loader = Issue::Loader::IssueTimeline.new(@context, { focused_item_global_id: focused_item.global_relay_id })
      assert_equal focused_item, loader.focused_item.async_entries.sync.first
    end

    # A B C D E
    # A E -> C is focused, params after_cursor D, before_cursor B,

    test "returns nil for focused item if item is deleted" do
      focused_item = @ordered_issue_events.fifth
      focused_item.destroy
      loader = Issue::Loader::IssueTimeline.new(@context, { focused_item_global_id: focused_item.global_relay_id })
      assert_nil loader.focused_item
    end

    test "returns entry for focused item if previous item is deleted" do
      focused_item = @ordered_issue_events.fifth
      @ordered_issue_events.fourth.destroy
      loader = Issue::Loader::IssueTimeline.new(@context, { focused_item_global_id: focused_item.global_relay_id })
      assert_equal focused_item, loader.focused_item.async_entries.sync.first
    end

    test "returns nil for focused item if focused_item_global_id is not in timeline" do
      loader = Issue::Loader::IssueTimeline.new(@context, { focused_item_global_id: "fakeglobal_id" })
      assert_nil loader.focused_item
    end
  end

  context "#next_page_hidden_items_count" do
    test "returns 0 if there aren't more items than we display" do
      loader = Issue::Loader::IssueTimeline.new(@context, {})
      assert_equal 10, loader.total_count
      assert_equal 30, loader.instance_variable_get("@page_size")
      assert_equal 0, loader.next_page_hidden_items_count
    end

    test "returns number of hidden items if they aren't all displayed" do
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 1 })
      assert_equal 10, loader.total_count
      assert_equal 1, loader.instance_variable_get("@page_size")
      assert_equal 8, loader.next_page_hidden_items_count
    end

    # technically we shouldn't be able to end up here but there are UI bugs and custom URLs that could result in this scenario so guard against it.
    test "returns 0 if we focus an item at the end of the timeline" do
      after_cursor = get_cursor(@ordered_issue_events.third)
      focused_item = @ordered_issue_events.last
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 1, after_cursor: after_cursor, focused_item_global_id: focused_item.global_relay_id })
      assert_equal 0, loader.next_page_hidden_items_count
    end

    test "returns correct count if before_cursor item is destroyed" do
      after_cursor = get_cursor(@ordered_issue_events.second)
      before_cursor = get_cursor(@ordered_issue_events[8])

      @ordered_issue_events[8].destroy!

      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, after_cursor: after_cursor, before_cursor: before_cursor })
      assert_equal 4, loader.next_page_hidden_items_count
    end

    # this can happen if we 'load more' items that have been deleted (commits forced pushed away for example)
    test "returns correct count if after_cursor item is last item" do
      after_cursor = get_cursor(@ordered_issue_events.last)

      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, after_cursor: after_cursor, before_cursor: after_cursor })
      assert_equal 0, loader.next_page_hidden_items_count
    end
  end

  context "#previous_page_hidden_items_count" do
    test "returns 0 if no focused item specified" do
      loader = Issue::Loader::IssueTimeline.new(@context, {})
      assert_equal 0, loader.previous_page_hidden_items_count
    end

    test "returns number of items before focused item" do
      after_cursor = get_cursor(@ordered_issue_events.first)

      focused_item = @ordered_issue_events.fifth
      loader = Issue::Loader::IssueTimeline.new(@context, { after_cursor: after_cursor, focused_item_global_id: focused_item.global_relay_id })
      assert_equal 3, loader.previous_page_hidden_items_count
    end

    test "returns number of items before focused item after third item" do
      after_cursor = get_cursor(@ordered_issue_events.third)

      focused_item = @ordered_issue_events.fifth
      loader = Issue::Loader::IssueTimeline.new(@context, { after_cursor: after_cursor, focused_item_global_id: focused_item.global_relay_id })
      assert_equal 1, loader.previous_page_hidden_items_count
    end

    test "handles cursor correctly when some events got deleted (including event the after_cursor points to)" do
      after_cursor = get_cursor(@ordered_issue_events.first)

      focused_item = @ordered_issue_events.fifth

      @ordered_issue_events.first.destroy
      @ordered_issue_events.second.destroy
      loader = Issue::Loader::IssueTimeline.new(@context, { after_cursor: after_cursor, focused_item_global_id: focused_item.global_relay_id })
      assert_equal 2, loader.previous_page_hidden_items_count
    end
  end

  # When there is not a focused item we show one 'load more' button for the items between the last item
  # displayed in the first group of items and the first item in the second group of items (the next page).
  #
  #       -------------------------
  #     | first item in first group |
  #       -------------------------
  #                 |
  #                 |
  #       ------------------------
  #     | last item in first group |
  #       ------------------------
  #
  #        ---------------------
  #       |  load more button   |
  #       |     (next page)     |
  #        ---------------------
  #
  #       --------------------------
  #     | first item in second group |
  #       --------------------------
  #                 |
  #                 |
  #       --------------------------
  #     | last item in second group |
  #       --------------------------
  #
  context "cursors with no focused item" do
    context "#previous_page_after_cursor" do
      test "returns nil" do
        after_cursor = get_cursor(@ordered_issue_events.second)

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, after_cursor: after_cursor })
        assert_nil loader.previous_page_after_cursor
      end
    end

    context "#previous_page_before_cursor" do
      test "returns nil" do
        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2 })
        assert_nil loader.previous_page_before_cursor
      end
    end

    context "#next_page_after_cursor" do
      test "returns cursor of the last item in the first group of items displayed" do
        last_item_first_group_cursor = get_cursor(@ordered_issue_events.second)

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2 })
        assert_equal last_item_first_group_cursor, loader.next_page_after_cursor
      end
    end

    context "#next_page_before_cursor" do
      test "returns cursor of the first item in the second group of items displayed" do
        first_item_second_group_cursor = get_cursor(@ordered_issue_events[8])

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2 })
        assert_equal first_item_second_group_cursor, loader.next_page_before_cursor
      end
    end
  end

  # When there is a focused item we show two 'load more' buttons, one for the items between the last item
  # displayed in the first group of items and the focused item (the previous page) and one for the items
  # between the focused item and the first item in the second group of items (the next page).
  #
  #       -------------------------
  #     | first item in first group |
  #       -------------------------
  #                 |
  #                 |
  #       ------------------------
  #     | last item in first group |
  #       ------------------------
  #
  #
  #       -----------------------
  #      |  load more button #1  |
  #      |   (previous page)     |
  #       -----------------------
  #           ---------------
  #          | focused item  |
  #           ---------------
  #       -----------------------
  #      |  load more button #2  |
  #      |     (next page)       |
  #       -----------------------
  #
  #
  #       --------------------------
  #     | first item in second group |
  #       --------------------------
  #                 |
  #                 |
  #       --------------------------
  #     | last item in second group |
  #       --------------------------
  #
  context "cursors with focused item" do
    context "#previous_page_after_cursor" do
      # we pass in the after_cursor of the last item in the first group of items
      test "returns passed in after_cursor if specified" do
        focused_item = @ordered_issue_events.fifth
        after_cursor = get_cursor(@ordered_issue_events.second)

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, after_cursor: after_cursor, focused_item_global_id: focused_item.global_relay_id })
        assert_equal after_cursor, loader.previous_page_after_cursor
      end
    end

    context "#previous_page_before_cursor" do
      test "returns cursor of the focused item" do
        focused_item = @ordered_issue_events.fifth
        focused_cursor = get_cursor(focused_item)

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, focused_item_global_id: focused_item.global_relay_id })
        assert_equal focused_cursor, loader.previous_page_before_cursor
      end
    end

    context "#next_page_after_cursor" do
      test "returns cursor of the focused item" do
        focused_item = @ordered_issue_events.fifth
        focused_cursor = get_cursor(focused_item)

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, focused_item_global_id: focused_item.global_relay_id })
        assert_equal focused_cursor, loader.next_page_after_cursor
      end
    end

    context "#next_page_before_cursor" do
      # we pass in the before_cursor of the first item in the second group of items
      test "returns passed in before_cursor if specified" do
        focused_item = @ordered_issue_events.fifth
        before_cursor = get_cursor(@ordered_issue_events[8])

        loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, before_cursor: before_cursor, focused_item_global_id: focused_item.global_relay_id })
        assert_equal before_cursor, loader.next_page_before_cursor
      end
    end
  end

  context "#timeline_start" do
    test "returns focused item if there is a focused item" do
      focused_item = @ordered_issue_events.fifth
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, focused_item_global_id: focused_item.global_relay_id })

      assert_equal [focused_item], loader.timeline_start.async_entries.sync
    end

    test "returns first group of items when timeline is paginated" do
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2 })

      expected = @ordered_issue_events.take(2)
      assert_equal expected, loader.timeline_start.async_entries.sync
    end
  end

  context "#timeline_end" do
    test "returns empty array if loading additional items" do
      after_cursor = get_cursor(@ordered_issue_events.second)
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2, after_cursor: after_cursor })

      assert_equal [], loader.timeline_end.async_entries.sync
    end

    test "returns second group of items when timeline is paginated" do
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 2 })

      expected = @ordered_issue_events.last(2)
      assert_equal expected, loader.timeline_end.async_entries.sync
    end

    test "with since parameter, returns second group of items" do
      # 5 items per page, starting at 4th item
      since_date = @ordered_issue_events.fourth.created_at.iso8601
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 5, timeline_since: since_date })

      expected = @ordered_issue_events.last(1)
      assert_equal expected, loader.timeline_end.async_entries.sync
    end

    test "returns empty array if there are no more entries left for second group" do
      # 5 items per page, starting at 5th item means all items fit in first group
      since_date = @ordered_issue_events.fifth.created_at.iso8601
      loader = Issue::Loader::IssueTimeline.new(@context, { per_page: 5, timeline_since: since_date })

      assert_equal [], loader.timeline_end.async_entries.sync
    end
  end
end
