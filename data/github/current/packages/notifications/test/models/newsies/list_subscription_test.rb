# typed: false
# frozen_string_literal: true

require "test_helper"

module Newsies
  class ListSubscriptionTest < GitHub::TestCase
    setup do
      ListSubscription.delete_all
      @list_id = 1
      @user_id = 3
      @other_user_id = 4
    end

    context ".for_lists" do
      test "returns subscriptions for multiple lists of different types" do
        repo_list_1 = Newsies::List.new("Repository", 101)
        repo_list_2 = Newsies::List.new("Repository", 102)
        team_list_1 = Newsies::List.new("Team", 101)
        team_list_2 = Newsies::List.new("Team", 102)

        ListSubscription.subscribe(1, repo_list_1)
        ListSubscription.subscribe(2, repo_list_2)
        ListSubscription.subscribe(3, team_list_1)
        ListSubscription.subscribe(4, team_list_2)

        assert_equal [1], ListSubscription.for_lists([repo_list_1]).map(&:user_id)
        assert_same_elements [1, 2], ListSubscription.for_lists([repo_list_1, repo_list_2]).map(&:user_id)
        assert_same_elements [3, 4], ListSubscription.for_lists([team_list_1, team_list_2]).map(&:user_id)

        assert_same_elements [1, 4], ListSubscription.for_lists([repo_list_1, team_list_2]).map(&:user_id)
        assert_same_elements [1, 3, 4], ListSubscription.for_lists([repo_list_1, team_list_1, team_list_2]).map(&:user_id)
      end
    end

    context ".excluding_lists" do
      test "returns subscriptions excluding multiple lists of different types" do
        repo_list_1 = Newsies::List.new("Repository", 101)
        repo_list_2 = Newsies::List.new("Repository", 102)
        team_list_1 = Newsies::List.new("Team", 101)
        team_list_2 = Newsies::List.new("Team", 102)

        ListSubscription.subscribe(1, repo_list_1)
        ListSubscription.subscribe(2, repo_list_2)
        ListSubscription.subscribe(3, team_list_1)
        ListSubscription.subscribe(4, team_list_2)

        assert_same_elements [2, 3, 4], ListSubscription.excluding_lists([repo_list_1]).map(&:user_id)
        assert_same_elements [3, 4], ListSubscription.excluding_lists([repo_list_1, repo_list_2]).map(&:user_id)
        assert_same_elements [1, 2], ListSubscription.excluding_lists([team_list_1, team_list_2]).map(&:user_id)

        assert_same_elements [2, 3], ListSubscription.excluding_lists([repo_list_1, team_list_2]).map(&:user_id)
        assert_equal [2], ListSubscription.excluding_lists([repo_list_1, team_list_1, team_list_2]).map(&:user_id)
      end
    end

    context ".as_subscribers" do
      test "returns subscriber objects" do
        list = Newsies::List.new("Repository", @list_id)
        user_1 = @user_id
        user_2 = @user_id + 100

        time_1 = Time.parse("2018-12-11 09:15:30Z")
        time_2 = Time.parse("2018-12-11 08:15:30Z")

        Timecop.freeze(time_1) { ListSubscription.subscribe(user_1, list) }
        Timecop.freeze(time_2) { ListSubscription.ignore(user_2, list) }

        sub_1, sub_2 = ListSubscription.all.order(:user_id).as_subscribers

        assert_equal user_1, sub_1.user_id
        assert_equal time_1, sub_1.created_at
        assert_predicate sub_1, :is_valid
        refute_predicate sub_1, :is_ignored

        assert_equal user_2, sub_2.user_id
        assert_equal time_2, sub_2.created_at
        assert_predicate sub_2, :is_valid
        assert_predicate sub_2, :is_ignored
      end
    end

    context "#as_subscription" do
      test "creates a subscription" do
        Timecop.freeze(Time.now.change(usec: 0)) do
          repo = create(:repository)

          subscription = ListSubscription.create!(
            user_id: 1,
            list_type: "Repository",
            list_id: repo.id,
            created_at: Time.now,
            ignored: false
          ).reload.as_subscription

          assert_equal Newsies::List.to_object(repo), subscription.list
          assert_equal repo, subscription.list_object
          assert_nil subscription.thread
          assert_predicate subscription, :valid?
          refute_predicate subscription, :ignored?
          assert_equal "list", subscription.reason
          assert_equal Time.now, subscription.created_at
        end
      end
    end

    context "belongs_to list" do
      test "looks up list if it is a repository" do
        repo = create(:repository)

        list_subscription = ListSubscription.create!(
          user_id: 1,
          list_type: "Repository",
          list_id: repo.id,
          created_at: Time.now,
          ignored: false
        )

        assert_equal repo, list_subscription.list
      end

      test "looks up list if it is a team" do
        team = create(:team)

        list_subscription = ListSubscription.create!(
          user_id: 1,
          list_type: "Team",
          list_id: team.id,
          created_at: Time.now,
          ignored: false
        )

        assert_equal team, list_subscription.list
      end

      test "looks up list if it is a user" do
        user = create(:user)

        list_subscription = ListSubscription.create!(
          user_id: 1,
          list_type: "User",
          list_id: user.id,
          created_at: Time.now,
          ignored: false
        ).reload

        assert_equal user, list_subscription.list
      end

      test "looks up list if it is an organization" do
        org = create(:organization)

        list_subscription = ListSubscription.create!(
          user_id: 1,
          list_type: "Organization",
          list_id: org.id,
          created_at: Time.now,
          ignored: false
        ).reload

        assert_equal org, list_subscription.list
      end
    end

    context "ensure timezones are correct" do
      test "ActiveRecord write, ActiveRecord read gets the same time" do
        current_time = Time.parse("2018-12-11 09:15:30Z")

        ListSubscription.create!(
          user_id: 1,
          list_type: "Test",
          list_id: 1,
          created_at: current_time,
          ignored: false,
        )

        subscription = ListSubscription.first
        assert_equal current_time, subscription.created_at
        assert_equal "UTC", subscription.created_at.zone
      end
    end

    context ".auto_subscribe" do
      test "auto subscribes list with pending notification" do
        list = Newsies::List.new("Repository", @list_id)
        assert_unsubscribed([@user_id, list])
        ListSubscription.auto_subscribe(@user_id, list)
        assert_subscribed([@user_id, list]) do |status|
          assert_subscription_time status
        end

        found = false
        ListSubscription.subscriptions_to_notify do |user_id, lists|
          if user_id == @user_id && lists.include?(list)
            found = true
          end
        end
        assert found
      end

      test "auto subscribes list without pending notification" do
        args = [@user_id, Newsies::List.new("Repository", @list_id)]
        assert_unsubscribed(args)

        ListSubscription.auto_subscribe(args[0], args[1], false)

        assert_subscribed(args) do |status|
          assert_subscription_time status
        end

        ListSubscription.subscriptions_to_notify do |user_id, _list_ids|
          refute_equal @user_id, user_id
        end
      end

      test "auto subscribes existing list" do
        newsies_list = Newsies::List.new("Repository", @list_id)
        args = [@user_id, newsies_list]
        assert_unsubscribed(args)

        ListSubscription.subscribe(*args)
        ListSubscription.notified(@user_id, [newsies_list])

        assert_subscribed(args)

        # no change
        ListSubscription.auto_subscribe(*args)

        assert_subscribed(args)
        ListSubscription.subscriptions_to_notify do |user_id, _list_ids|
          refute_equal @user_id, user_id
        end
      end

      test "auto subscribes ignored list" do
        list = Newsies::List.new("Repository", @list_id)
        assert_unsubscribed([@user_id, list])

        ListSubscription.ignore(@user_id, list)

        assert_ignored([@user_id, list])

        # no change
        ListSubscription.auto_subscribe(@user_id, list)

        assert_ignored([@user_id, list])
        ListSubscription.subscriptions_to_notify do |user_id, _list_ids|
          refute_equal @user_id, user_id
        end
      end

      test "auto subscribe with list type" do
        team_list = Newsies::List.new("Team", @list_id)
        list = Newsies::List.new("Repository", @list_id)

        assert_unsubscribed([@user_id, list])
        assert_unsubscribed([@user_id, team_list])

        ListSubscription.auto_subscribe(@user_id, team_list)

        assert_unsubscribed([@user_id, list])
        assert_subscribed([@user_id, team_list])
      end
    end

    context ".subscribers" do
      test "lists subscribers" do
        list = Newsies::List.new("Repository", @list_id)
        assert_equal [], ListSubscription.subscribers(list)

        ListSubscription.subscribe(@user_id + 300, list)
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id + 100))
        ListSubscription.subscribe(@user_id + 200, list)
        ListSubscription.subscribe(@user_id, list)
        ListSubscription.ignore(@user_id + 100, list)

        subscribed_users = [@user_id, @user_id + 200, @user_id + 300]

        assert subs_1 = ListSubscription.subscribers(list, per_page: 2)
        assert_equal 2, subs_1.size
        assert_equal 2, subs_1.map(&:user_id).uniq.size
        assert subscribed_users.include?(subs_1[0].user_id), "Subscriber not in subscriber set"
        assert subscribed_users.include?(subs_1[1].user_id), "Subscriber not in subscriber set"

        assert subs_2 = ListSubscription.subscribers(list, { page: 2, per_page: 2 })
        assert_equal 1, subs_2.size
        assert_equal 1, subs_2.map(&:user_id).uniq.size
        assert subscribed_users.include?(subs_2[0].user_id), "Subscriber not in subscriber set"

        assert_equal subscribed_users, (subs_1.map(&:user_id) + subs_2.map(&:user_id)).sort
      end

      test "list subscribers applies max page size" do
        list = Newsies::List.new("Repository", @list_id)
        assert_equal [], ListSubscription.subscribers(list)

        ListSubscription.subscribe(@user_id + 100, list)
        ListSubscription.subscribe(@user_id + 200, list)
        ListSubscription.subscribe(@user_id + 300, list)

        ListSubscription.stub_const(:MAX_PAGE_SIZE, 2) do
          assert subs_1 = ListSubscription.subscribers(list, per_page: 100)
          assert_equal 2, subs_1.size
        end
      end

      test "list subscribers applies default page size" do
        list = Newsies::List.new("Repository", @list_id)
        assert_equal [], ListSubscription.subscribers(list)

        ListSubscription.subscribe(@user_id + 100, list)
        ListSubscription.subscribe(@user_id + 200, list)
        ListSubscription.subscribe(@user_id + 300, list)

        ListSubscription.stub_const(:DEFAULT_PAGE_SIZE, 1) do
          assert subs_1 = ListSubscription.subscribers(list)
          assert_equal 1, subs_1.size
        end
      end

      test "lists subscribers with list type" do
        team_list = Newsies::List.new("Team", @list_id)
        list = Newsies::List.new("Repository", @list_id)
        assert_equal [], ListSubscription.subscribers(team_list)
        assert_equal [], ListSubscription.subscribers(list)

        ListSubscription.subscribe(@user_id, team_list)
        ListSubscription.ignore(@user_id + 100, team_list)
        ListSubscription.subscribe(@user_id + 200, team_list)
        ListSubscription.subscribe(@user_id + 300, team_list)
        ListSubscription.subscribe(@user_id, list)

        team_subscribed_users = [@user_id, @user_id + 200, @user_id + 300]

        assert subs = ListSubscription.subscribers(list)
        assert_equal [@user_id], subs.map(&:user_id)

        assert subs_1 = ListSubscription.subscribers(team_list, per_page: 2)
        assert_equal 2, subs_1.size
        assert_equal 2, subs_1.map(&:user_id).uniq.size
        assert team_subscribed_users.include?(subs_1[0].user_id), "Subscriber not in subscriber set"
        assert team_subscribed_users.include?(subs_1[1].user_id), "Subscriber not in subscriber set"

        assert subs_2 = ListSubscription.subscribers(team_list, { page: 2, per_page: 2 })
        assert_equal 1, subs_2.size
        assert_equal 1, subs_2.map(&:user_id).uniq.size
        assert team_subscribed_users.include?(subs_2[0].user_id), "Subscriber not in subscriber set"

        assert_equal team_subscribed_users, (subs_1.map(&:user_id) + subs_2.map(&:user_id)).sort
      end

      test "subscriptions with same list id and different list type" do
        team_list = Newsies::List.new("Team", @list_id)
        list = Newsies::List.new("Repository", @list_id)
        assert_unsubscribed([@user_id, list])
        assert_unsubscribed([@other_user_id, list])
        assert_unsubscribed([@user_id, team_list])
        assert_unsubscribed([@other_user_id, team_list])

        ListSubscription.subscribe(@user_id, list)
        assert_subscribed([@user_id, list])
        assert_unsubscribed([@other_user_id, list])
        assert_unsubscribed([@user_id, team_list])
        assert_unsubscribed([@other_user_id, team_list])

        ListSubscription.subscribe(@other_user_id, team_list)
        assert_subscribed([@user_id, list])
        assert_unsubscribed([@other_user_id, list])
        assert_unsubscribed([@user_id, team_list])
        assert_subscribed([@other_user_id, team_list])

        assert_equal [@user_id], ListSubscription.subscribers(list).map(&:user_id)
        assert_equal [@other_user_id], ListSubscription.subscribers(team_list).map(&:user_id)

        ListSubscription.ignore(@other_user_id, team_list)
        assert_subscribed([@user_id, list])
        assert_unsubscribed([@other_user_id, list])
        assert_unsubscribed([@user_id, team_list])
        assert_ignored([@other_user_id, team_list])

        ListSubscription.ignore(@user_id, list)
        assert_ignored([@user_id, list])
        assert_unsubscribed([@other_user_id, list])
        assert_unsubscribed([@user_id, team_list])
        assert_ignored([@other_user_id, team_list])
      end
    end

    context ".subscribers_by_cursor" do
      test "lists subscribers by cursor" do
        first   = @user_id + 100
        second  = @user_id + 200
        third   = @user_id + 300
        fourth  = @user_id + 400
        fifth   = @user_id + 500
        sixth   = @user_id + 600
        seventh = @user_id + 700

        list = Newsies::List.new("Repository", @list_id)
        subscribers = [first, second, third, fourth, fifth, sixth, seventh]
        subscribers.each { |subscriber| ListSubscription.subscribe(subscriber, list) }

        assert_equal subscribers, ListSubscription.subscribers_by_cursor(list).map(&:user_id)

        options = { cursor: fourth, cursor_direction: :upwards, limit: 2 }
        assert_equal [fifth, sixth], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)

        options = { cursor: fifth, cursor_direction: :downwards, limit: 3 }
        assert_equal [second, third, fourth], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)

        options = { cursor: nil, cursor_direction: :downwards, limit: 3 }
        assert_equal [fifth, sixth, seventh], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)

        options = { cursor: nil, cursor_direction: :upwards, limit: 3 }
        assert_equal [first, second, third], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)

        options = { cursor: nil, cursor_direction: nil, limit: 3 }
        assert_equal [first, second, third], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)
      end

      test "ignores spammy users" do
        first = @user_id + 100
        second = @user_id + 200
        third = @user_id + 300

        list = Newsies::List.new("Repository", @list_id)
        subscribers = [first, second, third]
        subscribers.each { |subscriber| ListSubscription.subscribe(subscriber, list) }

        Newsies::HiddenUser.hide_user(second)

        options = { cursor: 1, cursor_direction: :upwards, exclude_spammy_users: false }
        assert_equal subscribers, ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)

        options = { cursor: 1, cursor_direction: :upwards, exclude_spammy_users: true }
        assert_equal [first, third], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)
      end

      test "lists subscribers by cursor with list type" do
        first   = @user_id + 100
        second  = @user_id + 200
        third   = @user_id + 300
        fourth  = @user_id + 400
        fifth   = @user_id + 500
        sixth   = @user_id + 600
        seventh = @user_id + 700

        team_list = Newsies::List.new("Team", @list_id)
        list = Newsies::List.new("Repository", @list_id)
        team_subscribers = [first, second, third, fourth, fifth, sixth, seventh]
        team_subscribers.each { |subscriber| ListSubscription.subscribe(subscriber, team_list) }

        repo_subscribers = [first, third, fifth]
        repo_subscribers.each { |subscriber| ListSubscription.subscribe(subscriber, list) }

        assert_equal team_subscribers, ListSubscription.subscribers_by_cursor(team_list, list_type: "Team").map(&:user_id)
        assert_equal repo_subscribers, ListSubscription.subscribers_by_cursor(list).map(&:user_id)

        options = { cursor: fourth, cursor_direction: :upwards, limit: 2, list_type: "Team" }
        assert_equal [fifth, sixth], ListSubscription.subscribers_by_cursor(team_list, options).map(&:user_id)

        options = { cursor: fifth, cursor_direction: :downwards, limit: 3, list_type: "Team" }
        assert_equal [second, third, fourth], ListSubscription.subscribers_by_cursor(team_list, options).map(&:user_id)

        options = { cursor: third, cursor_direction: :upwards, limit: 2 }
        assert_equal [fifth], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)

        options = { cursor: fifth, cursor_direction: :downwards, limit: 2 }
        assert_equal [first, third], ListSubscription.subscribers_by_cursor(list, options).map(&:user_id)
      end
    end

    context ".subscribed_user_ids" do
      test "raises without list" do
        assert_raises ArgumentError do
          ListSubscription.subscribed_user_ids(nil)
        end
      end

      test "subscribed user ids" do
        list = Newsies::List.new("Repository", @list_id)
        user1 = @user_id + 100
        user2 = @user_id + 200
        user3 = @user_id + 300

        assert_equal [], ListSubscription.subscribed_user_ids(list)

        ListSubscription.subscribe(user1, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(user2, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(user3, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id + 100))

        subscribed_users = [user1, user2, user3]
        assert_equal subscribed_users, ListSubscription.subscribed_user_ids(list)

        ListSubscription.ignore(user2, list)

        assert_equal subscribed_users, ListSubscription.subscribed_user_ids(list)
      end

      test "subscribed user ids with list type" do
        team_list = Newsies::List.new("Team", @list_id)
        list = Newsies::List.new("Repository", @list_id)
        user1 = @user_id + 100
        user2 = @user_id + 200
        user3 = @user_id + 300

        assert_equal [], ListSubscription.subscribed_user_ids(team_list)
        assert_equal [], ListSubscription.subscribed_user_ids(list)

        ListSubscription.subscribe(user1, Newsies::List.new("Team", @list_id))
        ListSubscription.subscribe(user2, Newsies::List.new("Team", @list_id))
        ListSubscription.subscribe(user3, Newsies::List.new("Team", @list_id))
        ListSubscription.subscribe(@user_id, list)

        subscribed_users = [@user_id + 100, @user_id + 200, @user_id + 300]
        assert_equal subscribed_users, ListSubscription.subscribed_user_ids(team_list)
        assert_equal [@user_id], ListSubscription.subscribed_user_ids(list)

        ListSubscription.ignore(user2, team_list)

        assert_equal subscribed_users, ListSubscription.subscribed_user_ids(team_list)
      end
    end

    context ".count" do
      test "counts subscribers, excluding ignores, for a given list" do
        team_list = Newsies::List.new("Team", @list_id)
        list = Newsies::List.new("Repository", @list_id)
        user1 = @user_id + 100
        user2 = @user_id + 200
        user3 = @user_id + 300

        assert_equal 0, ListSubscription.count(team_list)
        assert_equal 0, ListSubscription.count(list)

        ListSubscription.subscribe(user3, team_list)
        ListSubscription.subscribe(@user_id, list)
        ListSubscription.subscribe(user2, team_list)
        ListSubscription.ignore(user1, team_list)

        assert_equal 2, ListSubscription.count(team_list)
        assert_equal 1, ListSubscription.count(list)
      end

      test "does not include spammy users if exclude_spammy_users = true" do
        list = Newsies::List.new("Repository", @list_id)
        user1 = @user_id + 100
        user2 = @user_id + 200

        ListSubscription.subscribe(user1, list)
        ListSubscription.subscribe(user2, list)

        Newsies::HiddenUser.hide_user(user2)

        assert_equal 1, ListSubscription.count(list, exclude_spammy_users = true)
        assert_equal 2, ListSubscription.count(list, exclude_spammy_users = false)
      end
    end

    context ".each" do
      test "enumerates subscription list" do
        list = Newsies::List.new("Repository", @list_id)
        other_list = Newsies::List.new("Repository", @list_id + 100)
        user1 = @user_id + 100
        user2 = @user_id + 200

        ListSubscription.each(list) do |_ids|
          raise "Should have no subscribers yet"
        end

        ListSubscription.subscribe(@user_id, other_list)
        ListSubscription.subscribe(user2, list)
        ListSubscription.subscribe(@user_id, list)
        ListSubscription.ignore(user1, list)

        lists = [[[@user_id, true], [@user_id + 100]], [[@user_id + 200, true]]]
        ListSubscription.each(list, batch_size: 2) do |subs|
          expected = lists.shift
          assert_equal expected.size, subs.size
          subs.each do |sub|
            user_id, is_subscribed = expected.shift
            assert_equal user_id, sub.user_id
            assert_subscription_time sub
            if is_subscribed
              assert sub.valid?, sub.inspect
              assert sub.subscribed?, sub.inspect
              assert !sub.ignored?, sub.inspect
            else
              assert sub.valid?, sub.inspect
              assert !sub.subscribed?, sub.inspect
              assert sub.ignored?, sub.inspect
            end
          end
          assert_equal [], expected
        end
        assert_equal [], lists
      end

      test "enumerates subscription list with list type" do
        list = Newsies::List.new("Repository", @list_id)
        team_list = Newsies::List.new("Team", @list_id)
        other_team_list = Newsies::List.new("Team", @list_id + 100)
        user1 = @user_id + 100
        user2 = @user_id + 200

        ListSubscription.each(team_list) do |_ids|
          raise "Should have no subscribers yet"
        end

        ListSubscription.subscribe(@user_id, list)
        ListSubscription.subscribe(@user_id, team_list)
        ListSubscription.subscribe(@user_id, other_team_list)
        ListSubscription.ignore(user1, team_list)
        ListSubscription.subscribe(user2, team_list)

        lists = [
          [[@user_id, true], [@user_id + 100]],
          [[@user_id + 200, true]],
        ]

        ListSubscription.each(team_list, batch_size: 2) do |subs|
          expected = lists.shift
          assert_equal expected.size, subs.size
          subs.each do |sub|
            user_id, is_subscribed = expected.shift
            assert_equal user_id, sub.user_id
            assert_subscription_time sub
            if is_subscribed
              assert sub.valid?, sub.inspect
              assert sub.subscribed?, sub.inspect
              assert !sub.ignored?, sub.inspect
            else
              assert sub.valid?, sub.inspect
              assert !sub.subscribed?, sub.inspect
              assert sub.ignored?, sub.inspect
            end
          end
          assert_equal [], expected
        end
        assert_equal [], lists
      end
    end

    context ".subscribe" do
      test "checks status for missing subscription" do
        list = Newsies::List.new("Repository", @list_id)
        assert_unsubscribed([@user_id, list]) do |status|
          assert !status.mentioned?
        end
      end

      test "subscribes to list" do
        list = Newsies::List.new("Repository", @list_id)
        ListSubscription.subscribe(@user_id, list)

        assert_subscribed([@user_id, list]) do |status|
          assert !status.mentioned?
          assert_subscription_time status
          assert_equal "Repository", status.list_type
        end
      end

      test "subscribes to list with list type" do
        team_list = Newsies::List.new("Team", @list_id)
        ListSubscription.subscribe(@user_id, team_list)

        assert_subscribed([@user_id, team_list]) do |status|
          assert_subscription_time status
          assert_equal "Team", status.list_type
        end
      end
    end

    context ".ignore" do
      test "ignores list" do
        list = Newsies::List.new("Repository", @list_id)
        ListSubscription.ignore(@user_id, list)

        assert_ignored([@user_id, list]) do |status|
          assert_subscription_time status
        end
      end

      test "ignores list with list type" do
        team_list = Newsies::List.new("Team", @list_id)
        ListSubscription.ignore(@user_id, team_list)

        assert_ignored([@user_id, team_list]) do |status|
          assert_subscription_time status
          assert_equal "Team", status.list_type
        end
      end
    end

    context ".ignored" do
      test "checks ignored" do
        time = Time.parse("2018-12-11 09:15:30Z")

        Timecop.freeze(time) do
          list = Newsies::List.new("Repository", @list_id)
          list2 = Newsies::List.new("Repository", @list_id + 100)
          list3 = Newsies::List.new("Repository", @list_id + 200)
          user1 = @user_id + 100

          ListSubscription.ignore(@user_id, list)
          ListSubscription.subscribe @user_id, list2
          ListSubscription.ignore user1, list3

          ignored = ListSubscription.ignored @user_id, [list, list2, list3]
          assert_equal 1, ignored.size
          assert sub = ignored.shift
          assert_equal @list_id, sub.list_id
          assert_kind_of Time, sub.created_at
          assert_equal time, sub.created_at
          assert sub.ignored?
        end
      end

      test "checks ignored with list type" do
        time = Time.parse("2018-12-11 09:15:30Z")

        Timecop.freeze(time) do
          team_list = Newsies::List.new("Team", @list_id)
          team_list2 = Newsies::List.new("Team", @list_id + 100)
          team_list3 = Newsies::List.new("Team", @list_id + 200)
          ListSubscription.ignore(@user_id, team_list)
          ListSubscription.subscribe(@user_id, team_list2)
          ListSubscription.ignore(@user_id + 100, team_list3)

          ignored = ListSubscription.ignored @user_id, [team_list, team_list2, team_list3]
          assert_equal 1, ignored.size
          assert sub = ignored.shift
          assert_equal @list_id, sub.list_id
          assert_equal "Team", sub.list_type
          assert_kind_of Time, sub.created_at
          assert_equal time, sub.created_at
          assert sub.ignored?
        end
      end
    end

    context ".unsubscribe" do
      test "unsubscribes from list" do
        list = Newsies::List.new("Repository", @list_id)
        ListSubscription.subscribe(@user_id, list)
        assert_subscribed([@user_id, list])

        ListSubscription.unsubscribe(@user_id, list)
        assert_unsubscribed([@user_id, list])
      end

      test "unsubscribes from list with list type" do
        team_list = Newsies::List.new("Team", @list_id)
        ListSubscription.subscribe(@user_id, team_list)
        assert_subscribed([@user_id, team_list])

        ListSubscription.unsubscribe(@user_id, team_list)
        assert_unsubscribed([@user_id, team_list])
      end

      test "unsubscribes from lists" do
        list = Newsies::List.new("Repository", @list_id)
        list2 = Newsies::List.new("Repository", @list_id + 100)
        list3 = Newsies::List.new("Repository", @list_id + 200)

        ListSubscription.subscribe(@user_id, list)
        ListSubscription.subscribe(@user_id, list2)
        ListSubscription.subscribe(@user_id, list3)
        assert_subscribed([@user_id, list])
        assert_subscribed([@user_id, list2])
        assert_subscribed([@user_id, list3])

        ListSubscription.unsubscribe(@user_id, [list, list2])
        assert_unsubscribed([@user_id, list])
        assert_unsubscribed([@user_id, list2])
        assert_subscribed([@user_id, list3])
      end

      test "unsubscribes from multiple list types at once" do
        # uses the same ids, but different types to ensure we
        # remove the correct types
        list = Newsies::List.new("Repository", @list_id)
        list2 = Newsies::List.new("Repository", @list_id + 100)
        team_list = Newsies::List.new("Team", @list_id)
        team_list2 = Newsies::List.new("Team", @list_id + 100)

        ListSubscription.subscribe(@user_id, list)
        ListSubscription.subscribe(@user_id, list2)
        ListSubscription.subscribe(@user_id, team_list)
        ListSubscription.subscribe(@user_id, team_list2)

        ListSubscription.unsubscribe(@user_id, [list, team_list2])
        assert_unsubscribed([@user_id, list])
        assert_unsubscribed([@user_id, team_list2])

        assert_subscribed([@user_id, list2])
        assert_subscribed([@user_id, team_list])
      end

      test "unsubscribes from lists with list type" do
        list = Newsies::List.new("Repository", @list_id)
        list2 = Newsies::List.new("Repository", @list_id + 100)
        list3 = Newsies::List.new("Repository", @list_id + 200)
        team_list = Newsies::List.new("Team", @list_id)
        team_list2 = Newsies::List.new("Team", @list_id + 100)
        ListSubscription.subscribe(@user_id, team_list)
        ListSubscription.subscribe(@user_id, team_list2)
        ListSubscription.subscribe(@user_id, list)
        ListSubscription.subscribe(@user_id, list3)

        assert_subscribed([@user_id, team_list])
        assert_subscribed([@user_id, team_list2])
        assert_subscribed([@user_id, list3])

        # Test that we wouldn't unsubscribe the user from multiple lists with the
        # same ID, but different list types.
        ListSubscription.unsubscribe(@user_id, [list, list2])
        assert_unsubscribed([@user_id, list])
        assert_subscribed([@user_id, team_list])
        assert_subscribed([@user_id, team_list2])

        ListSubscription.unsubscribe(@user_id, [team_list, team_list2])
        assert_unsubscribed([@user_id, team_list])
        assert_unsubscribed([@user_id, team_list2])
        assert_subscribed([@user_id, list3])
      end

      test "unsubscribe does not fail when empty list ids provided" do
        ListSubscription.unsubscribe(@user_id, [])
        ListSubscription.unsubscribe(@user_id, [nil])
      end
    end

    context ".subscriptions" do
      test "lists all repository subscriptions" do
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(@user_id + 100, Newsies::List.new("Repository", @list_id))
        ListSubscription.ignore(@user_id, Newsies::List.new("Repository", @list_id + 100))

        subs = ListSubscription.subscriptions(@user_id, set: :all)
        assert_equal 2, subs.size
        assert sub1 = subs.detect { |sub| sub.list_id == @list_id }
        assert sub2 = subs.detect { |sub| sub.list_id == (@list_id + 100) }
        assert_equal "Repository", sub1.list_type
        assert_equal "Repository", sub2.list_type
        assert_subscription_time sub1
        assert_subscription_time sub2
        refute sub1.ignored?
        assert sub2.ignored?
      end

      test "lists all subscriptions with list type" do
        ListSubscription.subscribe(@user_id, Newsies::List.new("Team", @list_id))
        ListSubscription.subscribe(@user_id + 100, Newsies::List.new("Team", @list_id))
        ListSubscription.ignore(@user_id, Newsies::List.new("Team", @list_id + 100))
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id))

        subs = ListSubscription.subscriptions(@user_id, list_type: "Team", set: :all)
        assert_equal 2, subs.size
        assert sub1 = subs.detect { |sub| sub.list_id == @list_id }
        assert sub2 = subs.detect { |sub| sub.list_id == (@list_id + 100) }
        assert_equal "Team", sub1.list_type
        assert_equal "Team", sub2.list_type
        assert_subscription_time sub1
        assert_subscription_time sub2

        subs = ListSubscription.subscriptions(@user_id, set: :all, list_type: "Repository")
        assert_equal 1, subs.size
        assert sub1 = subs.detect { |sub| sub.list_id == @list_id }
        assert_equal "Repository", sub1.list_type
        assert_subscription_time sub1
      end

      test "lists valid subscriptions" do
        other_user_args = [@user_id + 100, @list_id]
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(@user_id + 100, Newsies::List.new("Repository", @list_id))
        ListSubscription.ignore(@user_id, Newsies::List.new("Repository", @list_id + 100))

        subs = ListSubscription.subscriptions(@user_id, set: :subscribed)
        assert_equal 1, subs.size
        assert subs.detect { |sub| sub.list_id == @list_id }
      end

      test "lists ignored subscriptions" do
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(@user_id + 100, Newsies::List.new("Repository", @list_id))
        ListSubscription.ignore(@user_id, Newsies::List.new("Repository", @list_id + 100))

        subs = ListSubscription.subscriptions(@user_id, set: :ignored)
        assert_equal 1, subs.size
        assert subs.detect { |sub| sub.list_id == (@list_id + 100) }
      end

      test "subscriptions with exclusions" do
        list = Newsies::List.new("Repository", @list_id)
        other_list = Newsies::List.new("Repository", @list_id + 100)
        ListSubscription.subscribe(@user_id, list)
        ListSubscription.subscribe(@user_id + 100, list)
        ListSubscription.ignore(@user_id, other_list)

        subs = ListSubscription.subscriptions(@user_id, set: :subscribed, excluding: [other_list])
        assert_equal 1, subs.size
        assert sub1 = subs.detect { |sub| sub.list_id == @list_id }
        assert_subscription_time sub1

        subs = ListSubscription.subscriptions(@user_id, set: :subscribed, excluding: [list, other_list])
        assert_equal 0, subs.size
      end

      test "subscriptions with sort" do
        sql = <<-SQL
          INSERT INTO `notification_subscriptions` (`user_id`, `list_id`, `ignored`, `notified`, `created_at`)
          VALUES (:user_id, :list_id, 0, true, :created_at)
        SQL

        [4, 3, 2, 1].each do |n|
          ListSubscription.connection.insert(Arel.sql(sql,
            user_id: 1,
            list_id: n,
            created_at: Time.utc(2014, 12, 8, 10 - n).to_formatted_s(:db_utc)))
        end

        assert_equal [4, 3, 2, 1], ListSubscription.subscriptions(1, sort: :asc).map(&:list_id)
        assert_equal [4, 3, 2, 1], ListSubscription.subscriptions(1, sort: "asc").map(&:list_id)
        assert_equal [1, 2, 3, 4], ListSubscription.subscriptions(1, sort: :desc).map(&:list_id)
        assert_equal [1, 2, 3, 4], ListSubscription.subscriptions(1, sort: "desc").map(&:list_id)
        assert_equal [4, 3], ListSubscription.subscriptions(1, page: 1, per_page: 2, sort: :asc).map(&:list_id)
        assert_equal [2, 1], ListSubscription.subscriptions(1, page: 2, per_page: 2, sort: "asc").map(&:list_id)
      end

      test "subscriptions sorts descending if page but no direction specified" do
        sql = <<-SQL
          INSERT INTO `notification_subscriptions` (`user_id`, `list_id`, `ignored`, `notified`, `created_at`)
          VALUES (:user_id, :list_id, 0, true, :created_at)
        SQL

        [4, 3, 2, 1].each do |n|
          ListSubscription.connection.insert(Arel.sql(sql,
            user_id: 1,
            list_id: n,
            created_at: Time.utc(2014, 12, 8, 10 - n).to_formatted_s(:db_utc)))
        end

        assert_equal [1, 2, 3, 4], ListSubscription.subscriptions(1, page: 1).map(&:list_id)
      end

      test "subscriptions with invalid sort option" do
        assert_raises ArgumentError do
          ListSubscription.subscriptions(1, sort: "tuna")
        end
      end

      test "paginates subscriptions" do
        user_id = 1
        sql = <<-SQL
          INSERT INTO `notification_subscriptions` (`user_id`, `list_id`, `ignored`, `notified`, `created_at`)
          VALUES (:user_id, :list_id, 0, true, :created_at)
        SQL

        [4, 3, 2, 1].each do |list_id|
          ListSubscription.connection.insert(Arel.sql(sql,
            user_id: user_id,
            list_id: list_id,
            created_at: Time.utc(2015, 1, 22, 10 - list_id).to_formatted_s(:db_utc)))
        end

        subscriptions = ListSubscription.subscriptions(user_id, set: :all, page: 1, per_page: 1)
        assert_equal 1, subscriptions.size
        assert_equal 1, subscriptions.first.list_id

        subscriptions = ListSubscription.subscriptions(user_id, set: :all, page: 2, per_page: 1)
        assert_equal 1, subscriptions.size
        assert_equal 2, subscriptions.first.list_id

        subscriptions = ListSubscription.subscriptions(user_id, set: :all, page: 3, per_page: 1)
        assert_equal 1, subscriptions.size
        assert_equal 3, subscriptions.first.list_id

        subscriptions = ListSubscription.subscriptions(user_id, set: :all, page: 4, per_page: 1)
        assert_equal 1, subscriptions.size
        assert_equal 4, subscriptions.first.list_id
      end

      test "subscriptions applies default page size" do
        first   = Newsies::List.new("Repository", @list_id + 100)
        second  = Newsies::List.new("Repository", @list_id + 200)
        third   = Newsies::List.new("Repository", @list_id + 300)
        ListSubscription.subscribe(@user_id, first)
        ListSubscription.subscribe(@user_id, second)
        ListSubscription.subscribe(@user_id, third)

        ListSubscription.stub_const(:DEFAULT_PAGE_SIZE, 2) do
          subscriptions = ListSubscription.subscriptions(@user_id, set: :all, page: 1)
          assert_equal 2, subscriptions.size
        end
      end
    end

    context ".status_all" do
      test "status all" do
        newsies_list = Newsies::List.new("Repository", 2)

        ListSubscription.subscribe(@user_id, newsies_list)
        ListSubscription.subscribe(@other_user_id, newsies_list)

        assert_subscribed_all([[@user_id, @other_user_id], newsies_list])
      end

      test "status all when user is not in db" do
        user1 = 1
        user2 = 2
        user3 = 3
        user4 = 4
        list = Newsies::List.new("Repository", 2)
        ListSubscription.subscribe(user1, list)
        ListSubscription.subscribe(user3, list)

        statuses = ListSubscription.status_all([user1, user2, user3, user4], list)

        assert_equal 4, statuses.size
        assert statuses[0].valid?
        assert !statuses[1].valid?
        assert statuses[2].valid?
        assert !statuses[3].valid?
      end
    end

    context ".subscriptions_by_cursor" do
      test "subscriptions by cursor" do
        first   = Newsies::List.new("Repository", @list_id + 100)
        second  = Newsies::List.new("Repository", @list_id + 200)
        third   = Newsies::List.new("Repository", @list_id + 300)
        fourth  = Newsies::List.new("Repository", @list_id + 400)
        fifth   = Newsies::List.new("Repository", @list_id + 500)
        sixth   = Newsies::List.new("Repository", @list_id + 600)
        seventh = Newsies::List.new("Repository", @list_id + 700)

        subscriptions = [first, second, third, fourth, fifth, sixth, seventh]
        subscriptions.each { |list| ListSubscription.subscribe(@user_id, list) }

        assert_equal subscriptions.map(&:id), ListSubscription.subscriptions_by_cursor(@user_id).map(&:list_id)

        options = { cursor: fourth.id, cursor_direction: :upwards, limit: 2 }
        assert_equal [fifth, sixth].map(&:id), ListSubscription.subscriptions_by_cursor(@user_id, options).map(&:list_id)

        options = { cursor: fifth.id, cursor_direction: :downwards, limit: 3 }
        assert_equal [second, third, fourth].map(&:id), ListSubscription.subscriptions_by_cursor(@user_id, options).map(&:list_id)

        options = {
          cursor: first.id,
          cursor_direction: :upwards,
          limit: 3,
          excluding: [first, second, fourth, fifth, sixth],
        }
        assert_equal [third, seventh].map(&:id), ListSubscription.subscriptions_by_cursor(@user_id, options).map(&:list_id)
      end

      test "subscriptions by cursor with list type" do
        first   = Newsies::List.new("Team", @list_id + 100)
        second  = Newsies::List.new("Team", @list_id + 200)
        third   = Newsies::List.new("Team", @list_id + 300)
        fourth  = Newsies::List.new("Team", @list_id + 400)
        fifth   = Newsies::List.new("Team", @list_id + 500)
        sixth   = Newsies::List.new("Team", @list_id + 600)
        seventh = Newsies::List.new("Team", @list_id + 700)

        team_subscriptions = [first, second, third, fourth, fifth, sixth, seventh]
        team_subscriptions.each { |list| ListSubscription.subscribe(@user_id, list) }

        assert_equal team_subscriptions.map(&:id), ListSubscription.subscriptions_by_cursor(@user_id, list_type: "Team").map(&:list_id)

        options = { cursor: fourth.id, cursor_direction: :upwards, limit: 2, list_type: "Team" }
        assert_equal [fifth, sixth].map(&:id), ListSubscription.subscriptions_by_cursor(@user_id, options).map(&:list_id)
        assert_equal %w[Team Team], ListSubscription.subscriptions_by_cursor(@user_id, options).map(&:list_type)

        options = { cursor: fifth.id, cursor_direction: :downwards, limit: 3, list_type: "Team" }
        assert_equal [second, third, fourth].map(&:id), ListSubscription.subscriptions_by_cursor(@user_id, options).map(&:list_id)
      end
    end

    context ".subscriptions_find_many" do
      test "subscriptions_find_many" do
        user_id = 5
        list_id = 10
        other_list_id = 11
        list = Newsies::List.new("Repository", list_id)
        other_list = Newsies::List.new("Repository", other_list_id)
        ListSubscription.subscribe user_id, list
        ListSubscription.subscribe user_id, other_list

        subs = ListSubscription.subscriptions_find_many(user_id, [list, other_list])
        assert_equal 2, subs.size
        assert sub1 = subs.detect { |sub| sub.list_id == list_id }
        assert sub2 = subs.detect { |sub| sub.list_id == other_list_id }
        assert_subscription_time sub1
        assert_subscription_time sub2
      end

      test "subscriptions_find_many with list type" do
        user_id = 5
        team_id = 10
        repo_id = 11
        other_team_id = 12

        team_list = Newsies::List.new("Team", team_id)
        other_team_list = Newsies::List.new("Team", other_team_id)
        repo_list = Newsies::List.new("Repository", repo_id)

        ListSubscription.subscribe user_id, team_list
        ListSubscription.subscribe user_id, other_team_list
        ListSubscription.subscribe user_id, repo_list

        team_subs = ListSubscription.subscriptions_find_many(user_id, [team_list, other_team_list])
        assert_equal 2, team_subs.size
        assert sub1 = team_subs.detect { |sub| sub.list_id == team_id }
        assert sub2 = team_subs.detect { |sub| sub.list_id == other_team_id }
        assert_subscription_time sub1
        assert_subscription_time sub2

        # If no list_type is specified, it falls back to "Repository"
        repo_subs = ListSubscription.subscriptions_find_many(user_id, [repo_list])
        assert_equal 1, repo_subs.size
        assert_subscription_time repo_subs.detect { |sub| sub.list_id == repo_id }
      end

      test "subscriptions_find_many ignores other user subscribed list ids" do
        user_id = 5
        list_id = 10
        other_user_id = 6
        other_list_id = 11
        list = Newsies::List.new("Repository", list_id)
        other_list = Newsies::List.new("Repository", other_list_id)
        ListSubscription.subscribe user_id, list
        ListSubscription.subscribe other_user_id, other_list

        subs = ListSubscription.subscriptions_find_many(user_id, [list, other_list])
        assert_equal 1, subs.size
        assert sub1 = subs.detect { |sub| sub.list_id == list_id }
        assert_subscription_time sub1
        assert_nil subs.detect { |sub| sub.list_id == other_list_id }
      end

      test "subscriptions_find_many ignores non existent list ids" do
        user_id = 5
        list_id = 10
        non_existent_list_id = 9_999
        list = Newsies::List.new("Repository", list_id)
        non_existent_list = Newsies::List.new("Repository", non_existent_list_id)
        ListSubscription.subscribe user_id, list

        subs = ListSubscription.subscriptions_find_many(user_id, [list, non_existent_list])
        assert_equal 1, subs.size
        assert subs.detect { |sub| sub.list_id == list_id }
      end

      test "subscriptions_find_many compacts nils" do
        user_id = 5
        subscriptions = ListSubscription.subscriptions_find_many(user_id, [nil, nil])
        assert_empty subscriptions
      end

      test "subscriptions_find_many does not query for empty array" do
        GitHub::SQL.any_instance.expects(:results).never
        assert_equal [], ListSubscription.subscriptions_find_many(@user_id, [])
      end

      test "subscriptions_find_many does not query for array with nils" do
        GitHub::SQL.any_instance.expects(:results).never
        assert_equal [], ListSubscription.subscriptions_find_many(@user_id, [nil, nil])
      end
    end

    context ".count_subscriptions" do
      test "count_subscriptions" do
        other_user_args = [@user_id + 100, @list_id]
        other_list_args = [@user_id, @list_id + 100]
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id + 50))
        ListSubscription.subscribe(@user_id + 100, Newsies::List.new("Repository", @list_id)) # other user, not counted
        ListSubscription.ignore(@user_id, Newsies::List.new("Repository", @list_id + 100))

        assert_equal 3, ListSubscription.count_subscriptions(@user_id, set: :all)
        assert_equal 2, ListSubscription.count_subscriptions(@user_id, set: :subscribed)
        assert_equal 1, ListSubscription.count_subscriptions(@user_id, set: :ignored)
      end

      test "count_subscriptions with list type" do
        ListSubscription.subscribe(@user_id, Newsies::List.new("Team", @list_id))
        ListSubscription.subscribe(@user_id, Newsies::List.new("Repository", @list_id))
        ListSubscription.subscribe(@user_id, Newsies::List.new("Team", @list_id + 50))
        ListSubscription.subscribe(@user_id + 100, Newsies::List.new("Team", @list_id)) # other user, not counted
        ListSubscription.ignore(@user_id, Newsies::List.new("Team", @list_id + 100))

        assert_equal 4, ListSubscription.count_subscriptions(@user_id, set: :all)
        assert_equal 3, ListSubscription.count_subscriptions(@user_id, set: :all, list_type: "Team")
        assert_equal 1, ListSubscription.count_subscriptions(@user_id, set: :all, list_type: "Repository")
        assert_equal 2, ListSubscription.count_subscriptions(@user_id, set: :subscribed, list_type: "Team")
        assert_equal 1, ListSubscription.count_subscriptions(@user_id, set: :ignored, list_type: "Team")
      end

      test "count_subscriptions excluding list ids" do
        user_id = 100
        other_user_id = 101
        list = Newsies::List.new("Repository", 100)
        list2 = Newsies::List.new("Repository", 200)
        list3 = Newsies::List.new("Repository", 300)
        ListSubscription.subscribe(user_id, list)
        ListSubscription.subscribe(user_id, list2)
        ListSubscription.ignore(user_id, list3)
        ListSubscription.subscribe(other_user_id, list)

        assert_equal 2, ListSubscription.count_subscriptions(user_id, set: :all, excluding: [list])
        assert_equal 1, ListSubscription.count_subscriptions(user_id, set: :subscribed, excluding: [list])
        assert_equal 0, ListSubscription.count_subscriptions(user_id, set: :ignored, excluding: [list3])
      end
    end

    context ".subscriptions_to_notify" do
      test "subscriptions_to_notify yields user and lists" do
        list_900 = Newsies::List.new("Repository", 900)
        list_901 = Newsies::List.new("Repository", 901)
        list_904 = Newsies::List.new("Repository", 904)
        ListSubscription.auto_subscribe(1, list_900)
        ListSubscription.auto_subscribe(1, list_901)
        ListSubscription.auto_subscribe(2, list_900)
        ListSubscription.auto_subscribe(2, list_904)

        calls = 0
        ListSubscription.subscriptions_to_notify do |user_id, lists|
          calls += 1
          case calls
          when 1
            assert_equal 1, user_id
            assert_equal [list_900, list_901], lists
          when 2
            assert_equal 2, user_id
            assert_equal [list_900, list_904], lists
          else
            raise "should not be called again"
          end
        end
        assert_equal 2, calls
      end

      test "subscriptions_to_notify with list type yields user and lists" do
        repo_900 = Newsies::List.new("Repository", 900)
        repo_901 = Newsies::List.new("Repository", 901)
        team_902 = Newsies::List.new("Team", 902)
        team_903 = Newsies::List.new("Team", 903)

        ListSubscription.auto_subscribe(1, repo_900)
        ListSubscription.auto_subscribe(1, repo_901)
        ListSubscription.auto_subscribe(1, team_902)
        ListSubscription.auto_subscribe(1, team_903)

        ListSubscription.subscriptions_to_notify do |user_id, lists|
          assert_equal 1, user_id
          assert_equal [repo_900, repo_901, team_902, team_903], lists
        end

        ListSubscription.subscriptions_to_notify(list_type: "Repository") do |user_id, lists|
          assert_equal 1, user_id
          assert_equal [repo_900, repo_901], lists
        end

        ListSubscription.subscriptions_to_notify(list_type: "Team") do |user_id, lists|
          assert_equal 1, user_id
          assert_equal [team_902, team_903], lists
        end
      end

      test "subscriptions_to_notify does not yield with no subscriptions" do
        ListSubscription.subscriptions_to_notify do |*args|
          fail "yielded but should not have: #{args.inspect}"
        end
      end
    end

    context ".notified" do
      test "notified" do
        list1 = Newsies::List.new("Repository", 900)
        list2 = Newsies::List.new("Repository", 901)
        list3 = Newsies::List.new("Repository", 902)
        ListSubscription.auto_subscribe(1, list1)
        ListSubscription.auto_subscribe(1, list2)
        ListSubscription.auto_subscribe(1, list3)

        ListSubscription.notified(1, [list1, list2])

        ListSubscription.subscriptions_to_notify do |user_id, lists|
          assert_equal 1, user_id
          assert_equal [list3], lists
        end
      end

      test "notified with list type" do
        repo_list1 = Newsies::List.new("Repository", 900)
        team_list1 = Newsies::List.new("Team", 900)
        team_list2 = Newsies::List.new("Team", 901)
        team_list3 = Newsies::List.new("Team", 902)
        ListSubscription.auto_subscribe(1, repo_list1)
        ListSubscription.auto_subscribe(1, team_list1)
        ListSubscription.auto_subscribe(1, team_list2)
        ListSubscription.auto_subscribe(1, team_list3)

        ListSubscription.notified(1, [team_list1, team_list2])

        ListSubscription.subscriptions_to_notify(list_type: "Team") do |user_id, lists|
          assert_equal 1, user_id
          assert_equal [team_list3], lists
        end

        ListSubscription.subscriptions_to_notify(list_type: "Repository") do |user_id, lists|
          assert_equal 1, user_id
          assert_equal [repo_list1], lists
        end
      end

      test "notified ignores nil array entries" do
        sql = <<-SQL
          SELECT count(*)
          FROM notification_subscriptions
          WHERE user_id = 1 and notified = 0
        SQL

        list = Newsies::List.new("Repository", 900)
        ListSubscription.auto_subscribe(1, list)
        assert_equal 1, ListSubscription.where(user_id: 1, notified: 0).count
        ListSubscription.notified(1, [nil, list])
        assert_equal 0, ListSubscription.where(user_id: 1, notified: 0).count
      end

      test "notified noops for empty array" do
        sql = <<-SQL
          SELECT count(*)
          FROM notification_subscriptions
          WHERE user_id = 1 and notified = 0
        SQL

        assert_nil ListSubscription.notified(1, [])
      end
    end

    private

    def assert_status(args)
      assert status = ListSubscription.status(*args.flatten), "no status found"
      yield status
    end

    def assert_status_all(args)
      statuses = ListSubscription.status_all(*args)
      refute statuses.empty?
      yield statuses
    end

    def assert_subscribed(args)
      assert_status(args) do |status|
        assert status.valid?, "status is not valid"
        assert status.subscribed?, "status is not subscribed"
        assert !status.ignored?, "status is ignored"
        yield status if block_given?
      end
    end

    def assert_subscribed_all(args)
      assert_status_all(args) do |statuses|
        statuses.each do |status|
          assert status.valid?, "status is not valid"
          assert status.subscribed?, "status is not subscribed"
          assert !status.ignored?, "status is ignored"
          yield status if block_given?
        end
      end
    end

    def assert_unsubscribed(args)
      assert_status(args) do |status|
        assert !status.valid?, "status is valid"
        assert !status.subscribed?, "status is subscribed"
        assert !status.ignored?, "status is ignored"
        yield status if block_given?
      end
    end

    def assert_ignored(args)
      assert_status(args) do |status|
        assert status.valid?, "status is not valid"
        assert !status.subscribed?, "status is subscribed"
        assert status.ignored?, "status is not ignored"
        yield status if block_given?
      end
    end

    def assert_subscription_time(status)
      now = Time.now.utc
      assert_kind_of Time, status.created_at, "status created_at is not a time"
      assert_in_delta now.to_f, status.created_at.to_f, 3.0, "Status#created_at doesn't match Time.now: #{status.created_at.inspect} != #{now.inspect}"
      assert status.created_at.utc?, "status created_at is not in utc"
      assert status.created_at > (Time.now.utc - 5), status.created_at.inspect
    end
  end
end
