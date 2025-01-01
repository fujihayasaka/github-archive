# typed: true
# frozen_string_literal: true

require "test_helper"

class DiscussionTimeline::ItemFinderTest < GitHub::TestCase
  def timeline_items_for(discussion)
    top_level_comments = discussion.comments.top_level
    events_and_event_groups = discussion.unsorted_filtered_and_grouped_events_for(@repo.owner)
    (top_level_comments + events_and_event_groups).sort_by(&:created_at)
  end

  fixtures do
    @repo = create(:repository, has_discussions: true)
    @source_discussion = create(:discussion, repository: @repo)
    @target_discussion = create(:discussion, repository: @repo)
    @reference = create(:cross_reference, source: @source_discussion, target: @target_discussion)
  end

  setup do
    @timeline_items = timeline_items_for(@target_discussion)
  end

  context "#between_cursors" do
    test "filters timeline items to those between two cursors" do
      first_comment = create(:discussion_comment, repository: @repo, body: "I am 1st comment",
        discussion: @target_discussion)
      second_comment = create(:discussion_comment, discussion: @target_discussion, body: "I am 2nd comment",
        repository: @repo)
      third_comment = create(:discussion_comment, discussion: @target_discussion, body: "I am 3rd comment",
        repository: @repo)
      item_finder = DiscussionTimeline::ItemFinder.new(@target_discussion, viewer: @repo.owner,
        timeline_items: [first_comment, second_comment, third_comment])

      item_finder.between_cursors(after: first_comment.global_relay_id, before: third_comment.global_relay_id)

      assert_equal [second_comment], item_finder.to_a
    end

    test "does not exclude timeline items when the given cursors are invalid" do
      first_comment = create(:discussion_comment, repository: @repo, body: "I am 1st comment",
        discussion: @target_discussion)
      second_comment = create(:discussion_comment, discussion: @target_discussion, body: "I am 2nd comment",
        repository: @repo)
      item_finder = DiscussionTimeline::ItemFinder.new(@target_discussion, viewer: @repo.owner,
        timeline_items: [first_comment, second_comment])

      item_finder.between_cursors(before: "some invalid cursor", after: "also not cool")

      assert_equal [first_comment, second_comment], item_finder.to_a
    end

    test "works when only before cursor is given" do
      first_comment = create(:discussion_comment, repository: @repo, body: "I am 1st comment",
        discussion: @target_discussion)
      second_comment = create(:discussion_comment, discussion: @target_discussion, body: "I am 2nd comment",
        repository: @repo)
      item_finder = DiscussionTimeline::ItemFinder.new(@target_discussion, viewer: @repo.owner,
        timeline_items: [first_comment, second_comment])

      item_finder.between_cursors(before: second_comment.global_relay_id, after: nil)

      assert_equal [first_comment], item_finder.to_a
    end

    test "works when only after cursor is given" do
      first_comment = create(:discussion_comment, repository: @repo, body: "I am 1st comment",
        discussion: @target_discussion)
      second_comment = create(:discussion_comment, discussion: @target_discussion, body: "I am 2nd comment",
        repository: @repo)
      item_finder = DiscussionTimeline::ItemFinder.new(@target_discussion, viewer: @repo.owner,
        timeline_items: [first_comment, second_comment])

      item_finder.between_cursors(before: nil, after: first_comment.global_relay_id)

      assert_equal [second_comment], item_finder.to_a
    end
  end

  context "#since" do
    test "returns items since a timestamp" do
      discussion = create(:discussion, repository: @repo)
      older_comment = travel_to(30.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      newer_comment = travel_to(10.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      timeline_items = timeline_items_for(discussion)

      item_finder = DiscussionTimeline::ItemFinder.new(discussion, viewer: @repo.owner, timeline_items: timeline_items)

      item_finder.since(20.minutes.ago)

      assert_equal [newer_comment.reload], item_finder.to_a
    end

    test "returns original items if comparing to string" do
      discussion = create(:discussion, repository: @repo)
      older_comment = travel_to(30.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      newer_comment = travel_to(10.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      timeline_items = timeline_items_for(discussion)

      item_finder = DiscussionTimeline::ItemFinder.new(discussion, viewer: @repo.owner, timeline_items: timeline_items)

      item_finder.since("abc")

      assert_equal [older_comment, newer_comment], item_finder.to_a
    end

    test "returns original items if comparing to nil" do
      discussion = create(:discussion, repository: @repo)
      older_comment = travel_to(30.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      newer_comment = travel_to(10.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      timeline_items = timeline_items_for(discussion)

      item_finder = DiscussionTimeline::ItemFinder.new(discussion, viewer: @repo.owner, timeline_items: timeline_items)

      item_finder.since(nil)

      assert_equal [older_comment, newer_comment], item_finder.to_a
    end
  end

  context "#sort_by" do
    test "sorts items by 'new'" do
      discussion = create(:discussion, repository: @repo)
      older_comment = travel_to(30.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      newer_comment = travel_to(10.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      timeline_items = timeline_items_for(discussion)

      item_finder = DiscussionTimeline::ItemFinder.new(discussion, viewer: @repo.owner, timeline_items: timeline_items)

      assert_equal [older_comment, newer_comment], item_finder.to_a

      item_finder.sort_by("new")

      assert_equal [newer_comment, older_comment], item_finder.to_a
    end

    test "sorts items by 'old'" do
      discussion = create(:discussion, repository: @repo)
      newer_comment = travel_to(10.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      older_comment = travel_to(30.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      timeline_items = timeline_items_for(discussion)

      item_finder = DiscussionTimeline::ItemFinder.new(discussion, viewer: @repo.owner, timeline_items: timeline_items)

      item_finder.sort_by("new")
      assert_equal [newer_comment, older_comment], item_finder.to_a

      item_finder.sort_by("old")
      assert_equal [older_comment, newer_comment], item_finder.to_a
    end

    test "sorts items by 'top'" do
      discussion = create(:discussion, repository: @repo)
      low_total_upvotes_comment = travel_to(30.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      medium_total_upvotes_comment = travel_to(8.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      high_total_upvotes_comment = travel_to(10.minutes.ago) { create(:discussion_comment, discussion: discussion) }
      create_list(:discussion_comment_vote, 5, comment: low_total_upvotes_comment, upvote: true)
      create_list(:discussion_comment_vote, 10, comment: medium_total_upvotes_comment, upvote: true)
      create_list(:discussion_comment_vote, 15, comment: high_total_upvotes_comment, upvote: true)

      timeline_items = timeline_items_for(discussion)

      item_finder = DiscussionTimeline::ItemFinder.new(discussion, viewer: @repo.owner, timeline_items: timeline_items)
      assert_equal [low_total_upvotes_comment, high_total_upvotes_comment, medium_total_upvotes_comment], item_finder.to_a

      item_finder.sort_by("top")
      assert_equal [high_total_upvotes_comment, medium_total_upvotes_comment, low_total_upvotes_comment], item_finder.to_a
    end
  end
end
