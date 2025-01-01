# typed: true
# frozen_string_literal: true

require "test_helper"

class NewsiesThreadTypeSubscriptionTest < GitHub::TestCase

  setup do
    Newsies::ThreadTypeSubscription.destroy_all
    @newsies_list = Newsies::List.new("Repository", 1)
    @newsies_list_2 = Newsies::List.new("Team", 2)
    @newsies_list_3 = Newsies::List.new("Repository", 3)
    @user_id = 1
    @user_id_2 = 2
  end

  context ".subscribe_to_thread_types" do
    test "subscribes user to multiple thread types" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, %w[Release Issue])

      assert_same_elements %w[Release Issue], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
    end

    test "will remove existing ones before inserting" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, ["PullRequest"])
      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, %w[Release Issue])
      assert_same_elements %w[Release Issue], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
    end

    test "will to remove existing records for a different list" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, ["PullRequest"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list_2, ["DiscussionPost"])
      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
      assert_same_elements ["DiscussionPost"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list_2)

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, %w[Release Issue])
      assert_same_elements %w[Release Issue], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
      assert_same_elements ["DiscussionPost"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list_2)
    end

    test "will not remove existing records for a different user" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, ["PullRequest"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id_2, @newsies_list, ["PullRequest"])
      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id_2, @newsies_list)

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, %w[Release Issue])
      assert_same_elements %w[Release Issue], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id_2, @newsies_list)
    end

    test "will not update any values if passed in values are nil" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, ["PullRequest"])
      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)

      mock_newsies_list = mock("mock_newsies_list")
      mock_newsies_list.stubs(:id).returns(nil)
      mock_newsies_list.stubs(:type).returns(nil)

      assert_raises ActiveRecord::NotNullViolation do
        Newsies::ThreadTypeSubscription.subscribe_to_thread_types(nil, mock_newsies_list, %w[Release Issue])
        Newsies::ThreadTypeSubscription.subscribe_to_thread_types(nil, @newsies_list, %w[Release Issue])
      end

      assert_same_elements ["PullRequest"], Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
    end
  end

  context ".unsubscribe_from_all_thread_types_for_multiple_lists" do
    test "unsubscribes user from all thread types for multiple_lists" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(@user_id, @newsies_list_2, ["DiscussionPost"])

      Newsies::ThreadTypeSubscription.unsubscribe_from_all_thread_types_for_multiple_lists(
        @user_id,
        [@newsies_list, @newsies_list_2])

      assert_empty Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list)
      assert_empty Newsies::ThreadTypeSubscription.subscribed_thread_types(@user_id, @newsies_list_2)
    end
  end

  context "scopes" do
    test "for_lists returns subscriptions for multiple lists of different types" do
      repo_list_1 = Newsies::List.new("Repository", 101)
      repo_list_2 = Newsies::List.new("Repository", 102)
      team_list_1 = Newsies::List.new("Team", 101)
      team_list_2 = Newsies::List.new("Team", 102)

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, repo_list_1, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(2, repo_list_2, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(3, team_list_1, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(4, team_list_2, ["Release"])

      assert_equal [1], Newsies::ThreadTypeSubscription.for_lists([repo_list_1]).map(&:user_id)
      assert_equal [1, 2], Newsies::ThreadTypeSubscription.for_lists([repo_list_1, repo_list_2]).map(&:user_id)
      assert_equal [3, 4], Newsies::ThreadTypeSubscription.for_lists([team_list_1, team_list_2]).map(&:user_id)

      assert_equal [1, 4], Newsies::ThreadTypeSubscription.for_lists([repo_list_1, team_list_2]).map(&:user_id)
      assert_equal [1, 3, 4], Newsies::ThreadTypeSubscription.for_lists([repo_list_1, team_list_1, team_list_2]).map(&:user_id)
    end

    test "for_threads returns subscriptions for multiple thread types for different lists" do
      list_1 = Newsies::List.new("Repository", 101)
      list_2 = Newsies::List.new("Repository", 102)

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, list_1, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(2, list_1, ["Issue"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(3, list_2, ["Release"])

      thread_1 = Newsies::Thread.new("Release", 10, list: list_1)
      thread_2 = Newsies::Thread.new("Issue", 11, list: list_1)
      thread_3 = Newsies::Thread.new("Release", 12, list: list_2)

      assert_equal [1], Newsies::ThreadTypeSubscription.for_threads([thread_1]).map(&:user_id)
      assert_equal [1, 3], Newsies::ThreadTypeSubscription.for_threads([thread_1, thread_3]).map(&:user_id)
      assert_equal [1, 2], Newsies::ThreadTypeSubscription.for_threads([thread_1, thread_2]).map(&:user_id)
    end

    test "for_list and for_thread_type scopes work as expected" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(2, @newsies_list, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(3, @newsies_list, ["Release"])

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(4, @newsies_list, ["Issue"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(5, @newsies_list_2, ["Release"])

      subscriptions = []
      Newsies::ThreadTypeSubscription.for_list(@newsies_list).for_thread_type("Release").find_each do |subscription|
        subscriptions << subscription
      end

      assert_equal [
        Newsies::ThreadTypeSubscription.where(user_id: 1).first,
        Newsies::ThreadTypeSubscription.where(user_id: 2).first,
        Newsies::ThreadTypeSubscription.where(user_id: 3).first,
      ], subscriptions
    end

    test "excluding_lists removes specified lists from results" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, ["Release"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(2, @newsies_list, ["Issue"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(3, @newsies_list_2, ["DiscussionPost"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(4, @newsies_list_3, ["Release"])

      assert_equal [
        3
      ], Newsies::ThreadTypeSubscription.excluding_lists([@newsies_list, @newsies_list_3]).map(&:user_id)
    end
  end

  context ".subscriptions" do
    test "returns one subscription object per list" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, %w[Release Issue])

      assert_equal [
        @newsies_list_3.id,
        @newsies_list.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1).map(&:list_id)
    end

    test "respects sort order" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, %w[Release Issue])

      assert_equal [
        @newsies_list_3.id,
        @newsies_list.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, sort: :desc).map(&:list_id)

      assert_equal [
        @newsies_list.id,
        @newsies_list_3.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, sort: :asc).map(&:list_id)
    end

    test "paginates by lists" do
      newsies_list_4 = Newsies::List.new("Repository", 4)

      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue PullRequest])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, %w[Release Issue PullRequest])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, newsies_list_4, %w[Release Issue PullRequest])

      assert_equal [
        newsies_list_4.id,
        @newsies_list_3.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, page: 1, per_page: 2).map(&:list_id)

      assert_equal [
        @newsies_list.id,
      ], Newsies::ThreadTypeSubscription.subscriptions(1, page: 2, per_page: 2).map(&:list_id)
    end

    test "filters subscriptions to list type" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_2, ["DiscussionPost"])

      assert_equal [
        @newsies_list.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, list_type: "Repository").map(&:list_id)
      assert_equal [
        @newsies_list_2.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, list_type: "Team").map(&:list_id)
    end

    test "filters subscriptions to thread type" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, ["Release"])

      assert_equal [
        @newsies_list_3.id,
        @newsies_list.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, thread_type: "Release").map(&:list_id)

      assert_equal [
        @newsies_list.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, thread_type: "Issue").map(&:list_id)
    end

    test "excludes list if given" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, ["Release"])

      assert_equal [
        @newsies_list.id
      ], Newsies::ThreadTypeSubscription.subscriptions(1, excluding: [@newsies_list_3]).map(&:list_id)
    end
  end

  context ".count_subscriptions" do
    test "counts by list type" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_2, ["DiscussionPost"])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, ["Release"])

      assert_equal 2, Newsies::ThreadTypeSubscription.count_subscriptions(1, list_type: "Repository")
      assert_equal 1, Newsies::ThreadTypeSubscription.count_subscriptions(1, list_type: "Team")
    end

    test "only counts subscriptions with the mentioned thread_type if present" do
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list, %w[Release Issue])
      Newsies::ThreadTypeSubscription.subscribe_to_thread_types(1, @newsies_list_3, ["Release"])

      assert_equal 2, Newsies::ThreadTypeSubscription.count_subscriptions(1, thread_type: "Release")
      assert_equal 1, Newsies::ThreadTypeSubscription.count_subscriptions(1, thread_type: "Issue")
    end
  end
end
