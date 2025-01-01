# typed: true
# frozen_string_literal: true

require "test_helper"

class NewsFeedEventGrouperTest < GitHub::TestCase
  context "#apply_grouping_policy" do
    test "groups PublicEvent events by actor" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::PUBLIC_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "PublicEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 1, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "PublicEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 2, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "PublicEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 3, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal events, groups[0]
      assert_empty grouper.ungrouped_events
    end

    test "does not group PublicEvent events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::PUBLIC_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "PublicEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 1, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "PublicEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 2, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "PublicEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 3, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "groups ReleaseEvent events by actor" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::RELEASE_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "ReleaseEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 1, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "ReleaseEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 2, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "ReleaseEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 3, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal events, groups[0]
      assert_empty grouper.ungrouped_events
    end

    test "does not group Release events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::PUBLIC_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "ReleaseEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 1, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "ReleaseEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 2, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "ReleaseEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 3, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "leaves event ungrouped when it does not fit with others" do
      now = Time.zone.now
      event1 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: create(:repository), id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "FollowEvent",
        payload: { actor: { login: "user-2" }, target: { login: "user-1" } },
        created_at: now, id: 3
      )
      event3 = Stratocaster::Event.new(
        event_type: "FollowEvent", id: 2,
        payload: { actor: { login: "user-3" }, target: { login: "user-1" } },
        created_at: now - (NewsFeedEventGrouper::FOLLOW_MAX_INTERVAL_IN_SECONDS - 300)
      )

      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_equal 1, groups.size
      assert_equal [event2, event3], groups[0]
      assert_equal [event1], grouper.ungrouped_events
    end

    test "does not group events by target with the same actor and target" do
      now = Time.zone.now
      repo = create(:repository)
      event1 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: repo, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: repo, id: 8, created_at: now
      )

      grouper = NewsFeedEventGrouper.new([event1, event2])

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal [event1, event2], grouper.ungrouped_events
    end

    test "groups events by target when that is the policy" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::FOLLOW_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "FollowEvent",
        payload: { actor: { login: "user-2" }, target: { login: "user-1" } },
        created_at: now, id: 1
      )
      event2 = Stratocaster::Event.new(
        event_type: "FollowEvent", id: 2,
        payload: { actor: { login: "user-3" }, target: { login: "user-1" } },
        created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "FollowEvent", id: 3,
        payload: { actor: { login: "user-4" }, target: { login: "user-1" } },
        created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_equal 1, groups.size
      assert_equal events, groups[0]
      assert_empty grouper.ungrouped_events
    end

    test "will not group events with differing actors when policy is :actor" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::FOLLOW_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "FollowEvent", id: 1,
        payload: { actor: { login: "user-2" }, target: { login: "user-1" } },
        created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "FollowEvent", id: 2,
        payload: { actor: { login: "user-3" }, target: { login: "user-1" } },
        created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "FollowEvent", id: 3,
        payload: { actor: { login: "user-4" }, target: { login: "user-1" } },
        created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "will not group events with differing targets when policy is :target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::WATCH_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: create(:repository), id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: create(:repository), id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: create(:repository), id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "groups events by actor when that is the policy" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::WATCH_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "WatchEvent", payload: { actor: { login: "user-1" } },
        repo: build(:repository), id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal events, groups[0]
      assert_empty grouper.ungrouped_events
    end

    test "groups PR review comment events by actor for the same pull request" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::PR_REVIEW_COMMENT_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "PullRequestReviewCommentEvent", payload: { actor: { login: "user-1" },
        pull_request: { id: 1 } }, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "PullRequestReviewCommentEvent", payload: { actor: { login: "user-1" },
        pull_request: { id: 1 } }, id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "PullRequestReviewCommentEvent", payload: { actor: { login: "user-1" },
        pull_request: { id: 2 } }, id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal [event1, event2], groups[0]
      assert_equal [event3], grouper.ungrouped_events
    end

    test "does not group PR review comment events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::PR_REVIEW_COMMENT_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "PullRequestReviewCommentEvent", payload: { actor: { login: "user-1" },
        pull_request: { id: 1 } }, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "PullRequestReviewCommentEvent", payload: { actor: { login: "user-1" },
        pull_request: { id: 1 } }, id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "PullRequestReviewCommentEvent", payload: { actor: { login: "user-1" },
        pull_request: { id: 2 } }, id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "groups issue comment events by actor for the same issue" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::ISSUE_COMMENT_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "IssueCommentEvent", payload: { actor: { login: "user-1" }, issue: { id: 1 } },
        id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "IssueCommentEvent", payload: { actor: { login: "user-1" }, issue: { id: 1 } },
        id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "IssueCommentEvent", payload: { actor: { login: "user-1" }, issue: { id: 2 } },
        id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal [event1, event2], groups[0]
      assert_equal [event3], grouper.ungrouped_events
    end

    test "does not group issue comment events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "IssueCommentEvent", payload: { actor: { login: "user-1" }, issue: { id: 1 } },
        id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "IssueCommentEvent", payload: { actor: { login: "user-1" }, issue: { id: 1 } },
        id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "IssueCommentEvent", payload: { actor: { login: "user-1" }, issue: { id: 1 } },
        id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "groups create repo events by actor" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "repository" },
        repo: build(:repository), id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "repository" },
        repo: build(:repository), id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "repository" },
        repo: build(:repository), id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal events, groups[0]
      assert_empty grouper.ungrouped_events
    end

    test "does not group create repo events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      event1 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "repository" },
        repo: build(:repository), id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "repository" },
        repo: build(:repository), id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "repository" },
        repo: build(:repository), id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "groups create branch events by actor and repository" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      repo = create(:repository)
      event1 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "branch" },
        repo: repo, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "branch" },
        repo: repo, id: 8, created_at: now - (max_interval - 300)
      )
      other_repo = create(:repository)
      event3 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "branch" },
        repo: other_repo, id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal [event1, event2], groups[0]
      assert_equal [event3], grouper.ungrouped_events
    end

    test "does not group create branch events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      repo = build(:repository)
      event1 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "branch" },
        repo: repo, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "branch" },
        repo: repo, id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "branch" },
        repo: build(:repository), id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end

    test "groups create tag events by actor and repository" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      repo = create(:repository)
      event1 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "tag" },
        repo: repo, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "tag" },
        repo: repo, id: 8, created_at: now - (max_interval - 300)
      )
      other_repo = create(:repository)
      event3 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "tag" },
        repo: other_repo, id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:actor)

      assert_equal 1, groups.size
      assert_equal [event1, event2], groups[0]
      assert_equal [event3], grouper.ungrouped_events
    end

    test "does not group create tag events by target" do
      now = Time.zone.now
      max_interval = NewsFeedEventGrouper::CREATE_MAX_INTERVAL_IN_SECONDS
      repo = build(:repository)
      event1 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "tag" },
        repo: repo, id: 7, created_at: now
      )
      event2 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "tag" },
        repo: repo, id: 8, created_at: now - (max_interval - 300)
      )
      event3 = Stratocaster::Event.new(
        event_type: "CreateEvent", payload: { actor: { login: "user-1" }, ref_type: "tag" },
        repo: build(:repository), id: 9, created_at: now - (max_interval - 60)
      )
      events = [event1, event2, event3]
      grouper = NewsFeedEventGrouper.new(events)

      groups = grouper.apply_grouping_policy(:target)

      assert_empty groups
      assert_equal events, grouper.ungrouped_events
    end
  end
end
