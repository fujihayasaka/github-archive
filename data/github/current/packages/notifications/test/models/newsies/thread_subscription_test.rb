# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class NewsiesThreadSubscriptionTest < GitHub::TestCase
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @newsies_list = Newsies::List.new("Repository", 1)
      @newsies_thread = Newsies::Thread.new("Thread", 2, list: @newsies_list)
      @user_id = 3
      @user_id1 = 1
      @user_id2 = 2
      @user_list = [@user_id, @user_id1, @user_id2]
      @args = [@user_id, @newsies_thread]
    end

    setup do
      ThreadSubscription.destroy_all
    end

    context ".for_lists" do
      test "returns subscriptions for multiple lists of different types" do
        repo_list_1 = Newsies::List.new("Repository", 101)
        repo_thread_1 = Newsies::Thread.new("Issue", 1, list: repo_list_1)
        repo_list_2 = Newsies::List.new("Repository", 102)
        repo_thread_2 = Newsies::Thread.new("Issue", 2, list: repo_list_2)
        team_list_1 = Newsies::List.new("Team", 101)
        team_thread_1 = Newsies::Thread.new("DiscussionPost", 1, list: team_list_1)
        team_list_2 = Newsies::List.new("Team", 102)
        team_thread_2 = Newsies::Thread.new("DiscussionPost", 2, list: team_list_2)

        ThreadSubscription.subscribe(1, repo_thread_1, "manual")
        ThreadSubscription.subscribe(2, repo_thread_2, "manual")
        ThreadSubscription.subscribe(3, team_thread_1, "manual")
        ThreadSubscription.subscribe(4, team_thread_2, "manual")

        assert_same_elements [1], ThreadSubscription.for_lists([repo_list_1]).map(&:user_id)
        assert_same_elements [1, 2], ThreadSubscription.for_lists([repo_list_1, repo_list_2]).map(&:user_id)
        assert_same_elements [3, 4], ThreadSubscription.for_lists([team_list_1, team_list_2]).map(&:user_id)

        assert_same_elements [1, 4], ThreadSubscription.for_lists([repo_list_1, team_list_2]).map(&:user_id)
        assert_same_elements [1, 3, 4], ThreadSubscription.for_lists([repo_list_1, team_list_1, team_list_2]).map(&:user_id)
      end
    end

    context ".for_threads" do
      test "returns subscriptions for multiple threads" do
        repo_list_1 = Newsies::List.new("Repository", 101)
        repo_thread_1 = Newsies::Thread.new("Issue", 1, list: repo_list_1)
        repo_list_2 = Newsies::List.new("Repository", 102)
        repo_thread_2 = Newsies::Thread.new("Issue", 2, list: repo_list_2)
        team_list_1 = Newsies::List.new("Team", 101)
        team_thread_1 = Newsies::Thread.new("DiscussionPost", 1, list: team_list_1)
        team_list_2 = Newsies::List.new("Team", 102)
        team_thread_2 = Newsies::Thread.new("DiscussionPost", 2, list: team_list_2)

        ThreadSubscription.subscribe(1, repo_thread_1, "manual")
        ThreadSubscription.subscribe(2, repo_thread_2, "manual")
        ThreadSubscription.subscribe(3, team_thread_1, "manual")
        ThreadSubscription.subscribe(4, team_thread_2, "manual")

        assert_same_elements [1], ThreadSubscription.for_threads([repo_thread_1]).map(&:user_id)
        assert_same_elements [1, 2], ThreadSubscription.for_threads([repo_thread_1, repo_thread_2]).map(&:user_id)
        assert_same_elements [3, 4], ThreadSubscription.for_threads([team_thread_1, team_thread_2]).map(&:user_id)

        assert_same_elements [1, 4], ThreadSubscription.for_threads([repo_thread_1, team_thread_2]).map(&:user_id)
        assert_same_elements [1, 3, 4], ThreadSubscription.for_threads([repo_thread_1, team_thread_1, team_thread_2]).map(&:user_id)
      end
    end

    context "force_index" do
      test "by default does not force an index" do
        query = ThreadSubscription.for_user(1).force_index
        refute_includes query.to_sql, "FORCE INDEX"
      end

      test "does not force an index if querying by thread key" do
        query = ThreadSubscription.for_user(1)
                  .for_list(Newsies::List.new("Repository", 2))
                  .where(reason: "manual")
                  .where(thread_key: "Issue;1")
                  .excluding_ignored
                  .force_index
        refute_includes query.to_sql, "FORCE INDEX"
      end

      test "does not force an index if querying by created_at" do
        query = ThreadSubscription.for_user(1)
                  .for_list(Newsies::List.new("Repository", 2))
                  .where(reason: "manual")
                  .where(thread_key: "Issue;1")
                  .excluding_ignored
                  .order(created_at: :desc)
                  .force_index
        refute_includes query.to_sql, "FORCE INDEX"
      end

      test "forces an index if additional column is id" do
        query = ThreadSubscription.for_user(1)
                  .for_list(Newsies::List.new("Repository", 2))
                  .where(reason: "manual")
                  .where("id > 1")
                  .excluding_ignored
                  .force_index

        assert_includes query.to_sql, "FORCE INDEX (`index_on_list_id_user_id_reason_list_type_ignored`)"
      end

      test "uses index_on_list_id_user_id_reason_list_type_ignored if all it's columns are in the query" do
        query = ThreadSubscription.for_user(1)
                  .for_list(Newsies::List.new("Repository", 2))
                  .where(reason: "manual")
                  .excluding_ignored
                  .force_index

        assert_includes query.to_sql, "FORCE INDEX (`index_on_list_id_user_id_reason_list_type_ignored`)"
      end

      test "uses index_on_user_id_list_type_ignored if all it's columns are in the query" do
        query = ThreadSubscription.for_user(1)
                  .where(list_type: "Repository")
                  .excluding_ignored
                  .force_index

        assert_includes query.to_sql, "FORCE INDEX (`index_on_user_id_list_type_ignored`)"
      end

      test "uses index_on_list_id_user_id_list_type_ignored if all it's columns are in the query" do
        query = ThreadSubscription.for_user(1)
                  .for_list(Newsies::List.new("Repository", 2))
                  .excluding_ignored
                  .force_index

        assert_includes query.to_sql, "FORCE INDEX (`index_on_list_id_user_id_list_type_ignored`)"
      end

      test "uses index_on_user_id_reason_list_type_ignored if all it's columns are in the query" do
        query = ThreadSubscription.for_user(1)
                  .where(list_type: "Repository", reason: "manual")
                  .excluding_ignored
                  .force_index

        assert_includes query.to_sql, "FORCE INDEX (`index_on_user_id_reason_list_type_ignored`)"
      end

      test "use user_id_and_ignored_and_list_type_and_list_id_and_thread_key if experiment on user_id presents " do
        query = ThreadSubscription.for_user(1)
                                  .for_list(Newsies::List.new("Repository", 2))
                                  .excluding_ignored
                                  .force_user_id_index
        assert_includes query.to_sql, "FORCE INDEX (`user_id_and_ignored_and_list_type_and_list_id_and_thread_key`)"
      end
    end

    context ".cursor_paginate" do
      test "returns an ascending page of data" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: one, direction: :asc, limit: 2)
          .pluck(:id)

        assert_equal [two, three], paginated_subscription_ids
      end

      test "returns a descending page of data" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: five, direction: :desc, limit: 2)
          .pluck(:id)

        assert_equal [four, three], paginated_subscription_ids
      end

      test "includes one extra item for the next page in ascending order when asked" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: one, direction: :asc, limit: 2, reveal_next_page: true)
          .pluck(:id)

        assert_equal [two, three, four], paginated_subscription_ids
      end

      test "includes one extra item for the next page in descending when asked" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: five, direction: :desc, limit: 2, reveal_next_page: true)
          .pluck(:id)

        assert_equal [four, three, two], paginated_subscription_ids
      end

      test "includes one extra item for the previous page in ascending order when asked" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: one, direction: :asc, limit: 2, reveal_previous_page: true)
          .pluck(:id)

        assert_equal [one, two, three], paginated_subscription_ids
      end

      test "includes one extra item for the previous page in descending order when asked" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: five, direction: :desc, limit: 2, reveal_previous_page: true)
          .pluck(:id)

        assert_equal [five, four, three], paginated_subscription_ids
      end

      test "includes extra items on either side for a page in ascending order when asked" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: one, direction: :asc, limit: 2, reveal_previous_page: true, reveal_next_page: true)
          .pluck(:id)

        assert_equal [one, two, three, four], paginated_subscription_ids
      end

      test "includes extra items on either side for a page in descending order when asked" do
        5.times { |user_id| ThreadSubscription.subscribe(user_id, @newsies_thread, "manual") }
        one, two, three, four, five = ThreadSubscription.order(id: :asc).pluck(:id)

        paginated_subscription_ids = ThreadSubscription
          .cursor_paginate(cursor: five, direction: :desc, limit: 2, reveal_previous_page: true, reveal_next_page: true)
          .pluck(:id)

        assert_equal [five, four, three, two], paginated_subscription_ids
      end
    end

    context ".each" do
      test "enumerates subscription list" do
        other_list = Newsies::List.new(@newsies_list.type, @newsies_list.id + 100)
        other_list_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id + 100, list: other_list)
        other_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id + 100, list: @newsies_list)

        ThreadSubscription.each(@newsies_thread) do |_ids|
          raise "Should have no subscribers yet"
        end

        # subscriptions that should not be returned
        ThreadSubscription.subscribe(@user_id, other_thread, "manual")
        ThreadSubscription.subscribe(@user_id, other_list_thread, "manual")

        # subscriptions that should not be returned
        ThreadSubscription.subscribe(@user_id + 200, @newsies_thread, reason: "booya")
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        ThreadSubscription.ignore(@user_id + 100, @newsies_thread)
        ThreadSubscription.subscribe(@user_id + 300, @newsies_thread, { reason: "manual" }, ["issue_closed"])

        # grab all subscriptions in pages
        all_subs = T.let([], T::Array[Newsies::Subscriber])
        ThreadSubscription.stub_const(:MAX_PAGE_SIZE, 2) do
          ThreadSubscription.each(@newsies_thread) { |subs| all_subs += subs }
        end

        assert_equal 4, all_subs.length

        # user: @user_id
        assert_equal @user_id, T.must(all_subs[0]).user_id
        assert_equal "manual", T.must(all_subs[0]).reason
        assert_predicate all_subs[0], :valid?
        assert_predicate all_subs[0], :subscribed?
        assert_subscription_time all_subs[0]

        # user: @user_id + 100
        assert_equal @user_id + 100, T.must(all_subs[1]).user_id
        assert_predicate all_subs[1], :valid?
        refute_predicate all_subs[1], :subscribed?
        assert_predicate all_subs[1], :ignored?

        # user: @user_id + 200
        assert_equal @user_id + 200, T.must(all_subs[2]).user_id
        assert_equal "booya", T.must(all_subs[2]).reason
        assert_predicate all_subs[2], :valid?
        assert_predicate all_subs[2], :subscribed?
        assert_subscription_time all_subs[2]

        # user: @user_id + 300
        assert_equal @user_id + 300, T.must(all_subs[3]).user_id
        assert_equal "manual", T.must(all_subs[3]).reason
        assert_predicate all_subs[3], :valid?
        assert_predicate all_subs[3], :subscribed?
        assert_subscription_time all_subs[3]
        assert_equal ["issue_closed"], T.must(all_subs[3]).events
      end
    end

    context ".status" do
      test "checks status for missing subscription" do
        assert_unsubscribed(@args) do |status|
          refute_predicate status, :mentioned?
          refute_predicate status, :reason?
          assert_kind_of Time, status.created_at
          assert status.created_at.utc?
          assert status.created_at < Time.utc(2009)
        end
      end

      test "events are included in subscription if present" do
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", ["closed"])

        assert_subscribed(@args) do |status|
          assert_equal ["closed"], status.events
        end
      end
    end

    context ".subscribe" do
      test "subscribes to thread" do
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")

        assert_subscribed(@args) do |status|
          assert !status.mentioned?
          assert_subscription_time status
        end
      end

      test "raises if subscribing to thread without reason" do
        err = assert_raises ArgumentError do
          ThreadSubscription.subscribe(*@args)
        end

        assert_match /Cannot subscribe users*/, err.message
      end

      test "overrides ignored if exists" do
        ThreadSubscription.ignore(@user_id, @newsies_thread)
        assert_ignored(@args)

        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        assert_subscribed(@args)
      end

      test "subscribes to thread with legacy reason" do
        ThreadSubscription.subscribe(*@args + %w(booya))

        assert_subscribed(@args) do |status|
          assert !status.mentioned?
          assert status.reason?
          assert !status.reason?("booya")
          assert status.reason?("yolo")
        end
      end

      test "subscribes to thread with reason" do
        ThreadSubscription.subscribe(*@args + [{ reason: "booya" }])

        assert_subscribed(@args) do |status|
          assert !status.mentioned?
          assert status.reason?
          assert !status.reason?("booya")
          assert status.reason?("yolo")
        end
      end

      test "subscribes without forcing reason" do
        options = ThreadSubscribeOptions.fill(reason: "booya")
        args = @args + [options]
        ThreadSubscription.subscribe(*args)
        assert_subscribed(@args) do |status|
          assert_equal "booya", status.reason
        end

        options.reason = "foo"
        ThreadSubscription.subscribe(*args)

        assert_subscribed(@args) do |status|
          assert_equal "booya", status.reason
        end
      end

      test "subscribes with forced reason" do
        options = ThreadSubscribeOptions.fill(reason: "booya")
        args = @args + [options]
        ThreadSubscription.subscribe(*args)
        assert_subscribed(@args) do |status|
          assert_equal "booya", status.reason
        end

        options.fill(reason: "foo", force: true)

        ThreadSubscription.subscribe(*args)

        assert_subscribed(@args) do |status|
          assert_equal "foo", status.reason
        end
      end

      test "stores an empty array for events by default" do
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        assert_empty ThreadSubscription.last!.subscription_events
      end

      test "stores events as an array if passed" do
        events = %w[issue_opened issue_closed]
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", events)
        subscription_events = ThreadSubscription.last!.subscription_events

        assert_same_elements events, subscription_events.pluck(:event_name), subscription_events.inspect

        # Also make sure we're setting timestamps for all newly created subscription events.
        assert subscription_events.all? { |e| e.created_at && e.updated_at }
      end

      test "updates events if the subscription already existed" do
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        assert_empty ThreadSubscription.last!.subscription_events

        events = %w[issue_opened issue_closed]
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", events)
        assert_same_elements events, ThreadSubscription.last!.subscription_events.pluck(:event_name)

        events = ["issue_closed"]
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", events)
        assert_same_elements events, ThreadSubscription.last!.subscription_events.pluck(:event_name)
      end

      test "removes existing events if called with no events" do
        events = %w[issue_opened issue_closed]
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", events)
        assert_same_elements events, ThreadSubscription.last!.subscription_events.pluck(:event_name)

        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        assert_empty ThreadSubscription.last!.subscription_events
      end
    end

    context ".subscribe_all" do
      test "subscribes all to thread" do
        list = Newsies::List.new("Repository", 2)
        thread = Newsies::Thread.new("Thread", 3, list: list)
        ThreadSubscription.subscribe_all(@user_list, thread, "manual")
        assert_subscribed_all([@user_list, thread])
      end

      test "subscribes all to thread with reason" do
        list = Newsies::List.new("Repository", 2)
        thread = Newsies::Thread.new("Thread", 3, list: list)
        ThreadSubscription.subscribe_all(@user_list, thread, "booya")
        assert_subscribed_all([@user_list, thread]) do |status|
          assert !status.mentioned?
          assert status.reason == "booya"
        end
      end

      test "subscribes all with forced reason" do
        list = Newsies::List.new("Repository", 2)
        thread = Newsies::Thread.new("Thread", 3, list: list)
        ThreadSubscription.subscribe_all(@user_list, thread, "subscribed")

        assert_subscribed_all([@user_list, thread]) do |status|
          assert status.reason?
          assert status.reason == "subscribed"
          assert !status.mentioned?
        end

        ThreadSubscription.subscribe_all(@user_list, thread, { reason: "team-mentioned", force: true })

        assert_subscribed_all([@user_list, thread]) do |status|
          assert status.reason?
          assert status.reason == "team-mentioned"
          assert status.mentioned?
        end
      end

      test "subscribes all with non forced reason" do
        list = Newsies::List.new("Repository", 2)
        thread = Newsies::Thread.new("Thread", 3, list: list)
        ThreadSubscription.subscribe_all(@user_list, thread, "subscribed")

        assert_subscribed_all([@user_list, thread]) do |status|
          assert status.reason?
          assert status.reason == "subscribed"
          assert !status.mentioned?
        end

        ThreadSubscription.subscribe_all(@user_list, thread, { reason: "team-mentioned" })

        assert_subscribed_all([@user_list, thread]) do |status|
          assert status.reason?
          assert status.reason == "subscribed"
          assert !status.mentioned?
        end
      end
    end

    context ".ignore" do
      test "ignores thread" do
        ThreadSubscription.ignore(*@args)

        assert_ignored(@args) do |status|
          assert_subscription_time status
        end
      end

      test "removes any subscription events" do
        events = %w[closed opened]
        args_with_events = @args + ["manual", events]
        ThreadSubscription.subscribe(*args_with_events)
        assert_same_elements events, SubscriptionEvent.all.pluck(:event_name)

        ThreadSubscription.ignore(*@args)

        assert_empty SubscriptionEvent.all
      end

      test "checks ignored" do
        other_list = Newsies::List.new(@newsies_list.type, @newsies_list.id + 100)
        other_list_2 = Newsies::List.new(@newsies_list.type, @newsies_list.id + 200)
        other_list_3 = Newsies::List.new(@newsies_list.type, @newsies_list.id + 200)
        other_list_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id, list: other_list)
        other_list_2_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id, list: other_list_2)
        other_list_3_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id, list: other_list_3)
        other_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id + 100, list: @newsies_list)
        other_user_id = @user_id + 100

        ThreadSubscription.ignore(@user_id, @newsies_thread)
        ThreadSubscription.ignore(@user_id, other_thread)
        ThreadSubscription.ignore(@user_id, other_list_thread)
        ThreadSubscription.ignore(other_user_id, @newsies_thread)

        threads = [
          @newsies_thread,
          other_thread,
          other_list_thread,
          other_list_2_thread,
          other_list_3_thread,
        ]

        values = ThreadSubscription.ignored(@user_id, threads)
        assert_equal 3, values.size
        sub1 = values.detect do |sub|
          sub.list_type == @newsies_thread.list_type &&
            sub.list_id == @newsies_thread.list_id &&
            sub.thread_type == @newsies_thread.type &&
            sub.thread_id == @newsies_thread.id.to_s
        end
        assert sub1
        sub2 = values.detect do |sub|
          sub.list_type == other_thread.list_type &&
            sub.list_id == other_thread.list_id &&
          sub.thread_type == other_thread.type &&
          sub.thread_id == other_thread.id.to_s
        end
        assert sub2
        sub3 = values.detect do |sub|
          sub.list_type == other_list_thread.list_type &&
            sub.list_id == other_list_thread.list_id &&
            sub.thread_type == other_list_thread.type &&
            sub.thread_id == other_list_thread.id.to_s
        end
        assert sub3
        assert_subscription_time sub1
        assert_subscription_time sub2
        assert_subscription_time sub3
      end
    end

    context ".subscribed_user_ids" do
      test "returns subscriber ids" do
        other_list = Newsies::List.new(@newsies_list.type, @newsies_list.id + 100)
        other_list_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id + 100, list: other_list)
        other_thread = Newsies::Thread.new(@newsies_thread.type, @newsies_thread.id + 100, list: @newsies_list)

        assert_equal [], ThreadSubscription.subscribed_user_ids(@newsies_list)
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        ThreadSubscription.subscribe(@user_id, other_list_thread, "manual")
        assert_equal [@user_id], ThreadSubscription.subscribed_user_ids(@newsies_list)

        ThreadSubscription.subscribe(@user_id, other_thread, "manual")
        assert_equal [@user_id], ThreadSubscription.subscribed_user_ids(@newsies_list), "does not return duplicates"

        ThreadSubscription.ignore(*@args)
        ThreadSubscription.ignore(@user_id, other_thread)
        assert_equal [@user_id], ThreadSubscription.subscribed_user_ids(@newsies_list), "includes ignored subs"
      end
    end

    context ".unsubscribe_thread" do
      test "unsubscribes from thread" do
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        assert_subscribed(@args)

        ThreadSubscription.unsubscribe_thread(@user_id, @newsies_thread)
        assert_unsubscribed(@args) do |status|
          assert_kind_of Time, status.created_at
          assert status.created_at.utc?
          assert status.created_at < Time.utc(2009)
        end
      end

      test "removes any subscription events" do
        events = %w[closed opened]
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", events)
        assert_same_elements events, SubscriptionEvent.all.pluck(:event_name)

        ThreadSubscription.unsubscribe_thread(@user_id, @newsies_thread)

        assert_empty SubscriptionEvent.all
      end
    end

    context ".status_all" do
      test "status all when user is not in db" do
        list = Newsies::List.new("Repository", 2)
        thread = Newsies::Thread.new("Thread", 3, list: list)
        user1 = 1
        user2 = 2
        user3 = 3
        user4 = 4

        ## subscribes 2 users
        ThreadSubscription.subscribe_all([user1, user2], thread, "mentioned")

        ## checks for 4 users [in_db, not_in_db, db, not_in_db]
        statuses = ThreadSubscription.status_all([user2, user3, user1, user4], thread)

        assert_equal 4, statuses.size
        assert_predicate statuses[0], :valid?
        refute_predicate statuses[1], :valid?
        assert_predicate statuses[2], :valid?
        refute_predicate statuses[3], :valid?
      end

      test "returns an empty reason if user ignores a thread" do
        # This test was added in https://github.com/github/github/pull/104367
        # to ensure we keep the legacy behavior which called `.to_s` on
        # the subscription's reason.

        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual")
        assert subscription = ThreadSubscription.status_all([@user_id], @newsies_thread).first

        assert_equal "manual", T.must(subscription).reason

        ThreadSubscription.ignore(@user_id, @newsies_thread)
        assert subscription = ThreadSubscription.status_all([@user_id], @newsies_thread).first

        assert_equal "", T.must(subscription).reason
      end

      test "includes the events in the subscription if present" do
        ThreadSubscription.subscribe(@user_id, @newsies_thread, "manual", ["closed"])
        ThreadSubscription.subscribe(@user_id + 1, @newsies_thread, "manual", ["opened"])

        subscriptions = ThreadSubscription.status_all([@user_id, @user_id + 1], @newsies_thread)
        subscription1 = subscriptions.first
        refute_nil subscription1
        assert_equal ["closed"], T.must(subscription1).events
        subscription2 = subscriptions.second
        refute_nil subscription2
        assert_equal ["opened"], subscription2.events
      end
    end

    context "#async_thread" do
      test "resolves to Issue for issue subscription" do
        @user = create(:user)
        @repo = create(:repository)
        @issue = create(:issue, repository: @repo)
        reason = "manual"

        GitHub.newsies.subscribe_to_thread(@user, @repo, @issue, reason)

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: @user.id,
            list_type: @repo.class.name,
            list_id: @repo.id,
            thread_key: "Issue;#{@issue.id}",
            reason: reason)
          .first!

        assert subscription
        assert_equal @issue, subscription.async_thread.sync
      end

      test "resolves to Discussion for discussion subscription" do
        user = create(:user)
        discussion = create(:discussion)
        repo = discussion.repository
        reason = "manual"

        GitHub.newsies.subscribe_to_thread(user, repo, discussion, reason)

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: user.id,
            list_type: repo.class.name,
            list_id: repo.id,
            thread_key: "Discussion;#{discussion.id}",
            reason: reason)
          .first!

        assert subscription
        assert_equal discussion, subscription.async_thread.sync
      end

      test "resolves to PullRequest for regular pull request subscription" do
        @user = create(:user)
        @repo = create(:repository)
        @pull_request = create(:pull_request, :disable_disk_access)
        reason = "manual"

        GitHub.newsies.subscribe_to_thread(@user, @repo, @pull_request, reason)

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: @user.id,
            list_type: @repo.class.name,
            list_id: @repo.id,
            thread_key: "PullRequest;#{@pull_request.id}",
            reason: reason)
          .first!

        assert subscription
        assert_equal @pull_request, subscription.async_thread.sync
      end

      test "resolves to PullRequest for wonky pull request subscription" do
        @pull_request = create(:pull_request, :disable_disk_access)

        subscription = ThreadSubscription.create!(
          user_id: 42,
          list_type: "Repository",
          list_id: 42,
          ignored: false,

          # Use a thread key that exhibits https://github.com/github/github/issues/106506.
          thread_key: "Issue;#{@pull_request.issue.id}",

          reason: "manual")

        assert_equal @pull_request, subscription.async_thread.sync
      end

      test "resolves to nil for team discussion subscription" do
        @user = create(:user)
        @team = create(:team)
        @discussion = create(:discussion_post, team: @team)
        reason = "manual"

        GitHub.newsies.subscribe_to_thread(@user, @team, @discussion, reason)

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: @user.id,
            list_type: @team.class.name,
            list_id: @team.id,
            thread_key: "DiscussionPost;#{@discussion.id}",
            reason: reason)
          .first!

        assert subscription
        assert_nil subscription.async_thread.sync
      end

      test "resolves to nil for unknown thread type" do
        subscription = ThreadSubscription.create!(
          user_id: 42,
          list_type: "Repository",
          list_id: 42,
          ignored: false,
          thread_key: "Discussion;42",
          reason: "manual")

        # Thread does not exist, but attempt to load it should not raise an exception.
        assert_nil subscription.async_thread.sync
      end

      test "resolves to Gist for gist subscription", feature_enabled: :notifications_show_commit_subscriptions do
        repo = create(:repository, from_example: :simple)
        commit = create(:commit, repository: repo, author: repo.owner, changes: -> (files) {
          files.add("hello.rb", "puts 'Hello world'")
        })
        reason = "manual"

        GitHub.newsies.subscribe_to_thread(repo.owner, commit.repository, commit, reason)

        newsies_thread = Newsies::Thread.to_object(commit, list: Newsies::List.to_object(commit.repository))

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: repo.owner.id,
            list_type: newsies_thread.list.type,
            list_id: newsies_thread.list.id,
            thread_key: newsies_thread.key,
            reason: reason)
          .first!

        assert subscription
        assert_equal commit, subscription.async_thread.sync
      end

      test "resolves to Gist for gist subscription to nil when repo is missing", feature_enabled: :notifications_show_commit_subscriptions do
        repo = create(:repository, from_example: :simple)
        commit = create(:commit, repository: repo, author: repo.owner, changes: -> (files) {
          files.add("hello.rb", "puts 'Hello world'")
        })
        reason = "manual"

        GitHub.newsies.subscribe_to_thread(repo.owner, commit.repository, commit, reason)

        newsies_thread = Newsies::Thread.to_object(commit, list: Newsies::List.to_object(commit.repository))

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: repo.owner.id,
            list_type: newsies_thread.list.type,
            list_id: newsies_thread.list.id,
            thread_key: newsies_thread.key,
            reason: reason)
          .first!

        assert subscription
        repo.destroy!

        refute subscription.async_thread.sync
      end

      test "resolves to Gist for gist subscription to nil when commit is missing", feature_enabled: :notifications_show_commit_subscriptions do
        repo = create(:repository, from_example: :simple)
        commit = create(:commit, repository: repo, author: repo.owner, changes: -> (files) {
          files.add("hello.rb", "puts 'Hello world'")
        })
        reason = "manual"
        CommitsCollection.any_instance.stubs(:find).raises(GitRPC::ObjectMissing)

        GitHub.newsies.subscribe_to_thread(repo.owner, commit.repository, commit, reason)

        newsies_thread = Newsies::Thread.to_object(commit, list: Newsies::List.to_object(commit.repository))

        subscription = Newsies::ThreadSubscription
          .where(
            user_id: repo.owner.id,
            list_type: newsies_thread.list.type,
            list_id: newsies_thread.list.id,
            thread_key: newsies_thread.key,
            reason: reason)
          .first!

        assert subscription
        refute subscription.async_thread.sync
      end

    end

    def assert_status(args)
      assert status = ThreadSubscription.status(*args.flatten)
      yield status
    end

    def assert_status_all(args)
      statuses = ThreadSubscription.status_all(*args)
      refute_predicate statuses, :empty?
      yield statuses
    end

    def assert_subscribed(args)
      assert_status(args) do |status|
        assert_predicate status, :valid?
        assert_predicate status, :subscribed?
        refute_predicate status, :ignored?
        yield status if block_given?
      end
    end

    def assert_subscribed_all(args)
      assert_status_all(args) do |statuses|
        statuses.each do |status|
          assert_predicate status, :valid?
          assert_predicate status, :subscribed?
          refute_predicate status, :ignored?
          yield status if block_given?
        end
      end
    end

    def assert_unsubscribed(args)
      assert_status(args) do |status|
        refute_predicate status, :valid?
        refute_predicate status, :subscribed?
        refute_predicate status, :ignored?
        yield status if block_given?
      end
    end

    def assert_ignored(args)
      assert_status(args) do |status|
        assert_predicate status, :valid?
        refute_predicate status, :subscribed?
        assert_predicate status, :ignored?
        yield status if block_given?
      end
    end

    def assert_subscription_time(status)
      assert_kind_of Time, status.created_at
      assert_predicate status.created_at, :utc?
      assert status.created_at > (Time.now - 5), status.created_at.to_s
    end
  end
end
