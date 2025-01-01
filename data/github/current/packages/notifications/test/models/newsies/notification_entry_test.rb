# typed: true
# frozen_string_literal: true

require "test_helper"
require "github/middleware/stats"
require "github/memory_dogstats_d"

module Newsies
  class NotificationEntryTest < GitHub::TestCase
    Comment = Struct.new(:id)
    OtherThreadType = Struct.new(:id)

    fixtures do
      @list = create(:repository, id: 2)
      @list2 = create(:repository, id: 7)
      @user = create(:user)
      @user2 = create(:user)
    end

    setup do
      # We cannot summarize Stubs properly, but we aren't testing summarize
      # in these tests so stub it out
      NotificationSummary.any_instance.stubs(:summarize).returns(nil)

      @newsies_list = Newsies::List.to_object(@list)

      @thread1 = create(:issue, repository: @list)
      @comment1 = create(:issue_comment, issue: @thread1)
      @newsies_thread1 = Newsies::Thread.to_object(@thread1, list: @newsies_list)

      @thread2 = create(:issue, repository: @list)
      @comment2 = create(:issue_comment, issue: @thread2)
      @newsies_thread2 = Newsies::Thread.to_object(@thread2, list: @newsies_list)

      @newsies_list2 = Newsies::List.to_object(@list2)
      @thread3 = create(:issue, repository: @list2)
      @comment3 = create(:issue_comment, issue: @thread3)
      @newsies_thread3 = Newsies::Thread.to_object(@thread3, list: @newsies_list2)

      @summary1 = NotificationSummary.fetch_and_update!(@list, @thread1, @comment1)
      @summary2 = NotificationSummary.fetch_and_update!(@list, @thread2, @comment2)
      @summary3 = NotificationSummary.fetch_and_update!(@list2, @thread3, @comment3)
    end

    test "#flipper_id works like a user" do
      Timecop.freeze do
        NotificationEntry.insert(@user.id, @summary1, reason: "subscribed", event_time: 1.minute.ago)
      end
      entry = NotificationEntry.first!

      enable_feature_flag(:notification_entry_test_actor, @user)
      assert GitHub.flipper[:notification_entry_test_actor].enabled?(entry)

      disable_feature_flag(:notification_entry_test_actor, @user)
      refute GitHub.flipper[:notification_entry_test_actor].enabled?(entry)
    end

    test "#to_summary_hash uses NotificationSummary as source" do
      Timecop.freeze do
        NotificationEntry.insert(@user.id, @summary1, reason: "subscribed", event_time: 1.minute.ago)
      end

      NotificationSummary.any_instance.stubs(:to_summary_hash).returns({ source: :notification_summary })
      entry = NotificationEntry.first!

      assert_equal :notification_summary, entry.to_summary_hash[:source]
    end

    context "insert" do
      test "it inserts a new notification entry" do
        inserted_at = 10.minutes.ago.change(usec: 0).utc

        Timecop.freeze(inserted_at) do
          NotificationEntry.insert(@user.id, @summary1, reason: "subscribed", event_time: 1.minute.ago)
        end

        notification = NotificationEntry.for_user(@user.id).first!
        assert_predicate notification, :unread?
        assert_equal inserted_at, notification.updated_at
        assert_equal "subscribed", notification.reason
        assert_equal @summary1.list_owner_id, notification.owner_id
        assert_equal @summary1.thread_author_id, notification.author_id
      end

      test "does not fail if author doesn't exist" do
        inserted_at = 10.minutes.ago.change(usec: 0).utc
        NotificationSummary.any_instance.stubs(:thread_author_id).returns(nil)

        Timecop.freeze(inserted_at) do
          NotificationEntry.insert(@user.id, @summary1, reason: "subscribed", event_time: 1.minute.ago)
        end

        notification = NotificationEntry.for_user(@user.id).first!
        assert_nil notification.author_id
      end

      test "does not fail if owner doesn't exist" do
        inserted_at = 10.minutes.ago.change(usec: 0).utc
        NotificationSummary.any_instance.stubs(:list_owner_id).returns(nil)

        Timecop.freeze(inserted_at) do
          NotificationEntry.insert(@user.id, @summary1, reason: "subscribed", event_time: 1.minute.ago)
        end

        notification = NotificationEntry.for_user(@user.id).first!
        assert_nil notification.owner_id
      end

      test "does not update the notification entry updated_at when inserted with old event_time" do
        first_insert_at = 10.minutes.ago.change(usec: 0).utc

        Timecop.freeze(first_insert_at) do
          NotificationEntry.insert(@user.id, @summary1, event_time: 1.minute.ago)
        end

        NotificationEntry.insert(@user.id, @summary1, event_time: 1.hour.ago)

        notification = NotificationEntry.for_user(@user.id).first!
        assert_predicate notification, :unread?
        assert_equal first_insert_at, notification.updated_at
      end

      test "does not update the notification entry unread/last_read_at when inserted with old event_time" do
        first_insert_at = 10.minutes.ago.change(usec: 0).utc
        mark_read_at = 5.minutes.ago.change(usec: 0).utc

        Timecop.freeze(first_insert_at) do
          NotificationEntry.insert(@user.id, @summary1, event_time: Time.now)
        end

        Timecop.freeze(mark_read_at) do
          NotificationEntry.mark_all(Time.now, @user.id)
        end

        NotificationEntry.insert(@user.id, @summary1, event_time: 1.hour.ago)

        notification = NotificationEntry.for_user(@user.id).first!
        refute_predicate notification, :unread?
        assert_equal mark_read_at, notification.last_read_at
      end

      test "does update the reason if delivering an old event_time" do
        Timecop.freeze(10.minutes.ago) do
          NotificationEntry.insert(@user.id, @summary1, reason: "subscribed", event_time: Time.now)
        end

        NotificationEntry.insert(@user.id, @summary1, reason: "mention", event_time: 1.hour.ago)

        notification = NotificationEntry.for_user(@user.id).first!
        assert_equal "mention", notification.reason
      end

      test "updates the notification if delivering a newer event_time" do
        first_insert_at = 20.minutes.ago.change(usec: 0).utc
        mark_read_at = 15.minutes.ago.change(usec: 0).utc
        second_insert_at = 10.minutes.ago.change(usec: 0).utc

        Timecop.freeze(first_insert_at) do
          NotificationEntry.insert(@user.id, @summary1, event_time: 1.minute.ago, reason: "subscribed")

          notification = NotificationEntry.for_user(@user.id).first!
          assert_predicate notification, :unread?
          assert_equal first_insert_at, notification.updated_at
          assert_equal "subscribed", notification.reason
        end

        Timecop.freeze(mark_read_at) do
          NotificationEntry.mark_all(Time.now, @user.id)
          notification = NotificationEntry.for_user(@user.id).first
          refute_predicate notification, :unread?
        end

        Timecop.freeze(second_insert_at) do
          NotificationEntry.insert(@user.id, @summary1, event_time: 1.minute.ago, reason: "mention")
        end

        notification = NotificationEntry.for_user(@user.id).first!
        assert_predicate notification, :unread?
        assert_equal second_insert_at, notification.updated_at
        assert_equal "mention", notification.reason
      end
    end

    context ".mark_summary" do
      test "mark summary as read" do
        NotificationEntry.insert @user.id, @summary1
        time = Time.parse("2018-12-11 09:15:30Z")
        Timecop.freeze(time) do
          NotificationEntry.mark_summary(:read, @user.id, @summary1.id)
        end
        entry = NotificationEntry.for_user(@user.id).first!
        refute_predicate entry, :unread?
        assert_equal time, entry.last_read_at
      end

      test "mark summary as unread" do
        NotificationEntry.insert @user.id, @summary1
        time_at_read = Time.parse("2018-12-11 09:15:30Z")
        Timecop.freeze(time_at_read) do
          NotificationEntry.mark_summary(:read, @user.id, @summary1.id)
        end

        time_at_unread = Time.parse("2018-12-12 12:30:45Z")
        Timecop.freeze(time_at_unread) do
          NotificationEntry.mark_summary(:unread, @user.id, @summary1.id)
        end

        entry = NotificationEntry.for_user(@user.id).first!
        assert_predicate entry, :unread?
        assert_equal time_at_read, entry.last_read_at
      end
    end

    context ".mark_summaries" do
      test "markes multiple summaries as read for a user" do
        NotificationEntry.insert(@user.id, @summary1)
        NotificationEntry.insert(@user.id, @summary2)
        NotificationEntry.insert(@user.id, @summary3)
        NotificationEntry.insert(@user2.id, @summary1)

        time = Time.parse("2018-12-11 09:15:30Z")

        Timecop.freeze(time) do
          NotificationEntry.mark_summaries(:read, @user.id, [@summary1.id, @summary2.id])

          should_be_read = NotificationEntry.for_user(@user.id).for_summaries([@summary1.id, @summary2.id])
          should_be_read.each do |summary|
            refute_predicate summary, :unread?
            assert_equal time, summary.last_read_at
          end

          should_be_unread = NotificationEntry.for_user(@user.id).for_summaries([@summary3.id]) +
                             NotificationEntry.for_user(@user2.id).for_summaries([@summary1.id])
          should_be_unread.each do |summary|
            assert_predicate summary, :unread?
          end
        end
      end

      test "markes multiple summaries as unread for a user" do
        NotificationEntry.insert(@user.id, @summary1)
        NotificationEntry.insert(@user.id, @summary2)
        NotificationEntry.insert(@user.id, @summary3)
        NotificationEntry.insert(@user2.id, @summary1)

        time_at_read = Time.parse("2018-12-11 09:15:30Z")
        Timecop.freeze(time_at_read) do
          NotificationEntry.mark_summaries(:read, @user.id, [@summary1.id, @summary2.id, @summary3.id])
          NotificationEntry.mark_summaries(:read, @user2.id, [@summary1.id])
        end

        time_at_unread = Time.parse("2018-12-12 12:30:45Z")
        Timecop.freeze(time_at_unread) do
          NotificationEntry.mark_summaries(:unread, @user.id, [@summary1.id, @summary2.id])

          should_be_unread = NotificationEntry.for_user(@user.id).for_summaries([@summary1.id, @summary2.id])
          should_be_unread.each do |summary|
            assert_predicate summary, :unread?
            assert_equal time_at_read, summary.last_read_at
          end

          should_be_read = NotificationEntry.for_user(@user.id).for_summaries([@summary3.id]) +
                             NotificationEntry.for_user(@user2.id).for_summaries([@summary1.id])
          should_be_read.each do |summary|
            refute_predicate summary, :unread?
          end
        end
      end
    end

    context ".mark_thread" do
      test "mark thread read" do
        NotificationEntry.insert @user.id, @summary1
        entry = NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).first
        assert_equal @summary1.id, entry.summary_id
        assert_predicate entry, :unread?
        assert_nil entry.last_read_at

        time = Time.parse("2018-12-11 09:15:30Z")
        Timecop.freeze(time) do
          NotificationEntry.mark_thread(:read, @user.id, @newsies_thread1)

          entry = NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).first
          assert_equal @summary1.id, entry.summary_id
          refute_predicate entry, :unread?
          assert_equal time, entry.last_read_at
        end
      end

      test "mark thread unread" do
        NotificationEntry.insert @user.id, @summary1
        entry = NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).first

        time_read_at = Time.parse("2018-12-11 09:15:30Z")
        Timecop.freeze(time_read_at) do
          NotificationEntry.mark_thread(:read, @user.id, @newsies_thread1)

          entry.reload
          assert_equal @summary1.id, entry.summary_id
          refute_predicate entry, :unread?
          assert_equal time_read_at, entry.last_read_at
        end

        entry.reload
        assert_no_difference("entry.reload.last_read_at") do
          NotificationEntry.mark_thread(:unread, @user.id, @newsies_thread1)
        end
        assert_predicate entry, :unread?
      end
    end

    context ".delete" do
      test "deletes a given notification entry by summary id for a user" do
        NotificationEntry.insert @user.id, @summary1
        assert_equal 1, NotificationEntry.count(@user.id)

        NotificationEntry.delete(@user.id, @summary1.id)

        assert_equal 0, NotificationEntry.count(@user.id)
      end
    end

    context ".for_user_with_options" do
      test "returns all entries for a user" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user2.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id)
        assert_same_elements [@summary1.id, @summary2.id], results.map(&:summary_id)
      end

      test "returns all for a specific list with options[:list]" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        # @summary3 is on a different list
        NotificationEntry.insert @user.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id, list: @list)
        assert_same_elements [@summary1.id, @summary2.id], results.map(&:summary_id)
      end

      test "returns all for a specific thread_type with options[:list] and options[:thread_type]" do
        other_thread_type = create(:discussion_post)
        other_summary = NotificationSummary.fetch_and_update!(@list, other_thread_type, other_thread_type)
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, other_summary

        results = NotificationEntry.for_user_with_options(@user.id, list: @list, thread_type: @newsies_thread1.type)
        assert_equal [@summary1.id], results.map(&:summary_id)
      end

      test "returns only unread with options[:unread] = true" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.mark_summary :read, @user.id, @summary2.id

        results = NotificationEntry.for_user_with_options(@user.id, unread: true)
        assert_equal [@summary1.id], results.map(&:summary_id)
      end

      test "returns only those with participating reasons with options[:participating] = true" do
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        NotificationEntry.insert @user.id, @summary2

        results = NotificationEntry.for_user_with_options(@user.id, participating: true)
        assert_equal [@summary1.id], results.map(&:summary_id)
      end

      test "returns only those where the reason is in the options[:reasons] array" do
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        NotificationEntry.insert @user.id, @summary2, reason: "invitation"

        results = NotificationEntry.for_user_with_options(@user.id, reasons: ["invitation"])
        assert_equal [@summary2.id], results.map(&:summary_id)
      end

      test "returns nothing if the options[:reasons] array is empty" do
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        NotificationEntry.insert @user.id, @summary2, reason: "invitation"

        results = NotificationEntry.for_user_with_options(@user.id, reasons: [])
        assert_equal [], results.map(&:summary_id)
      end

      test "returns notifications where the list is in the options[:lists] array" do
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        # @summary3 is on a different list
        NotificationEntry.insert @user.id, @summary3, reason: "invitation"

        results = NotificationEntry.for_user_with_options(@user.id, lists: [@list2])
        assert_equal [@summary3.id], results.map(&:summary_id)
      end

      test "returns notifications where the lists are in the options[:lists] array" do
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        # @summary3 is on a different list
        NotificationEntry.insert @user.id, @summary3, reason: "invitation"

        results = NotificationEntry.for_user_with_options(@user.id, lists: [@list, @list2])
        assert_same_elements [@summary1.id, @summary3.id], results.map(&:summary_id)
      end

      test "returns nothing if the options[:lists] array is empty" do
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        NotificationEntry.insert @user.id, @summary2, reason: "invitation"

        results = NotificationEntry.for_user_with_options(@user.id, lists: [])
        assert_same_elements [], results.map(&:summary_id)
      end

      test "return nothing if the options[:list] contains a global relay id that the user cannot access" do
        random_repo = create(:repository, id: 8)
        NotificationEntry.insert @user.id, @summary1, reason: "manual"
        NotificationEntry.insert @user.id, @summary2, reason: "invitation"

        results = NotificationEntry.for_user_with_options(@user.id, lists: [random_repo])
        assert_equal [], results.map(&:summary_id)
      end

      test "for_user_with_options since and before date" do
        NotificationEntry.insert @user.id, @summary1

        NotificationEntry.connection.execute "UPDATE notification_entries set updated_at = '2000-1-1 00:00:00'"

        NotificationEntry.insert @user.id, @summary2

        since = NotificationEntry.for_user_with_options(@user.id, since: Time.utc(2010))
        assert_equal [@summary2.id], since.map(&:summary_id)

        before = NotificationEntry.for_user_with_options(@user.id, before: Time.utc(2010))
        assert_equal [@summary1.id], before.map(&:summary_id)
      end

      test "for_user_with_options excluding specific lists" do
        assert_equal @list,  @summary1.list
        assert_equal @list2, @summary3.list

        @team_list = create(:team, id: 10)
        discussion_post = DiscussionPost.new.tap { |post| post.id = 11 }
        @discussion_post_summary = NotificationSummary.fetch_and_update!(@team_list, discussion_post, nil)

        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary3
        NotificationEntry.insert @user.id, @discussion_post_summary

        excluding = [@summary1.list, @discussion_post_summary.list]
        results = NotificationEntry.for_user_with_options(@user.id, excluding: excluding)
        assert_equal [@summary3.id], results.map(&:summary_id)

        excluding = [@summary1.list, @summary3.list, @discussion_post_summary.list]
        assert_empty NotificationEntry.for_user_with_options(@user.id, excluding: excluding)
      end

      test "for_user_with_options for list type" do
        @team_list = Team.new.tap { |t| t.id = 10 }
        discussion_post = DiscussionPost.new.tap { |post| post.id = 11 }
        @discussion_post_summary = NotificationSummary.fetch_and_update!(@team_list, discussion_post, nil)

        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, @summary3
        NotificationEntry.insert @user.id, @discussion_post_summary

        results = NotificationEntry.for_user_with_options(@user.id, list_type: "Repository")
        expected = [@summary1.id, @summary2.id, @summary3.id]
        assert_same_elements expected, results.map(&:summary_id)

        results = NotificationEntry.for_user_with_options(@user.id, list_type: "Team")
        expected = [@discussion_post_summary.id]
        assert_same_elements expected, results.map(&:summary_id)
      end

      test "returns all for a specific thread_type with options[:thread_types]" do
        other_thread = create(:discussion_post)
        other_summary = NotificationSummary.fetch_and_update!(@list, other_thread, other_thread)
        other_newsies_thread = Newsies::Thread.to_object(other_thread, list: @list)
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, other_summary

        results = NotificationEntry.for_user_with_options(@user.id, list: @list, thread_types: [@newsies_thread1.type])
        assert_same_elements [@summary1.id], results.map(&:summary_id)

        results = NotificationEntry.for_user_with_options(@user.id, list: @list, thread_types: [@newsies_thread1.type, other_newsies_thread.type])
        assert_same_elements [@summary1.id, other_summary.id], results.map(&:summary_id)
      end

      test "handles commits correctly with options[:thread_types]" do
        # Have to use a real commit here to trigger the Grit::Commit edge case
        example_repo :with_tokens, @list
        commit = @list.heads.find("master").target

        commit_comment = create(:commit_comment,
          repository: @list,
          user: @user2,
          commit_id: commit.oid,
        )
        commit_comment_summary = NotificationSummary.fetch_and_update!(@list, commit, commit_comment)
        NotificationEntry.insert @user.id, commit_comment_summary

        assert_equal "#{@list.id};Grit::Commit;#{commit.oid}", NotificationEntry.pluck(:thread_key).last

        results = NotificationEntry.for_user_with_options(@user.id, list: @list, thread_types: ["Commit"])
        assert_equal [commit_comment_summary.id], results.map(&:summary_id)
      end

      test "force index (user_id, updated_at) if options.statuses has multiple values" do
        query = NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read, :inbox_unread])

        assert_includes query.to_sql, "FORCE INDEX (index_notification_entries_on_user_id_and_updated_at)"
      end

      test "force index (user_id, unread, updated_at) if options.statuses has a single value" do
        query = NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read])

        assert_includes query.to_sql, "FORCE INDEX (user_id_and_unread_and_updated_at)"
      end

      test "force index (user_id, unread, updated_at) if options.unread?" do
        query = NotificationEntry.for_user_with_options(@user.id, unread: true)

        assert_includes query.to_sql, "FORCE INDEX (user_id_and_unread_and_updated_at)"
      end

      test "force index (user_id, updated_at) if options.read?" do
        query = NotificationEntry.for_user_with_options(@user.id, read: true)

        assert_includes query.to_sql, "FORCE INDEX (index_notification_entries_on_user_id_and_updated_at)"
      end

      test "force index (user_id, updated_at) if multiple options passed" do
        query = NotificationEntry.for_user_with_options(@user.id, read: true, unread: true, statuses: [:archived])

        assert_includes query.to_sql, "FORCE INDEX (index_notification_entries_on_user_id_and_updated_at)"
      end

      test "does not force index if query filters on list_type or list_id" do
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], list_type: "Repository"), "FORCE INDEX"
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], list: Newsies::List.new("Repository", 1)), "FORCE INDEX"
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], lists: [Newsies::List.new("Repository", 1)]), "FORCE INDEX"
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], excluding: [Newsies::List.new("Repository", 1)]), "FORCE INDEX"
      end

      test "does not force index if query filters on reason" do
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], reasons: "mention"), "FORCE INDEX"
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], participating: true), "FORCE INDEX"
      end

      test "does not force index if query filters on saved" do
        refute_includes NotificationEntry.for_user_with_options(@user.id, statuses: [:inbox_read], saved: true), "FORCE INDEX"
      end

      test "for_user_with_options for owners" do
        NotificationEntry.insert @user.id, @summary1
        # @summary3 is on a different list
        NotificationEntry.insert @user.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id, owners: [@list2.owner])
        assert_equal [@summary3.id], results.map(&:summary_id)
      end

      test "for_user_with_options for exclude_owners" do
        NotificationEntry.insert @user.id, @summary1
        # @summary3 is on a different owner (@list2)
        NotificationEntry.insert @user.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id, exclude_owners_by_id: [@list2.owner.id])
        assert_equal [@summary1.id], results.map(&:summary_id)
      end

      test "for_user_with_options for exclude_owners takes presedence over owners filter" do
        NotificationEntry.insert @user.id, @summary1
        # @summary3 is on a different owner (@list2)
        NotificationEntry.insert @user.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id, exclude_owners_by_id: [@list2.owner.id], owners: [@list2.owner])
        assert_equal [], results.map(&:summary_id)
      end

      test "for_user_with_options for exclude_owners combines with owners filter" do
        rando_owner = create(:organization)
        NotificationEntry.insert @user.id, @summary1
        # @summary3 is on a different owner (@list2)
        NotificationEntry.insert @user.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id, exclude_owners_by_id: [@list2.owner.id], owners: [@list.owner])
        assert_equal [@summary1.id], results.map(&:summary_id)

        results = NotificationEntry.for_user_with_options(@user.id, exclude_owners_by_id: [@list2.owner.id], owners: [rando_owner])
        assert_equal [], results.map(&:summary_id)
      end

      test "for_user_with_options for authors" do
        NotificationEntry.insert @user.id, @summary1
        # @summary3 is on a different list
        NotificationEntry.insert @user.id, @summary3

        results = NotificationEntry.for_user_with_options(@user.id, authors: [@thread3.user])
        assert_equal [@summary3.id], results.map(&:summary_id)
      end


      test "for_user_with_options for focusing reasons" do
        user_id = @summary1.thread_author_id
        # @summary1 has same author as user who receives notification
        NotificationEntry.insert user_id, @summary1, reason: "assign"
        NotificationEntry.insert user_id, @summary2, reason: "invitation"

        results = NotificationEntry.for_user_with_options(user_id, focusing: user_id)
        assert_equal [@summary1.id], results.map(&:summary_id)
      end

      test "for_user_with_options for team_mention reason" do
        user_id = @summary1.thread_author_id
        # @summary1 has same author as user who receives notification
        NotificationEntry.insert user_id, @summary1, reason: "assign"
        NotificationEntry.insert user_id, @summary2, reason: "team_mention"

        results = NotificationEntry.for_user_with_options(user_id, team_mention: true)
        assert_equal [@summary2.id], results.map(&:summary_id)
      end

      test "for_user_with_options for not_focus_team_mentioned reasons" do
        user_id = @summary1.thread_author_id
        # @summary1 has same author as user who receives notification
        NotificationEntry.insert user_id, @summary1, reason: "assign"
        NotificationEntry.insert user_id, @summary2, reason: "invitation"
        NotificationEntry.insert user_id, @summary3, reason: "security_advisory_credit"

        results = NotificationEntry.for_user_with_options(user_id, not_focus_team_mentioned: user_id)
        assert_equal [@summary2.id, @summary3.id].sort, results.map(&:summary_id).sort
      end

      test "for_user_with_options for focusing reasons with author override" do
        user_id = @summary1.thread_author_id
        # @summary1 has same author as user who receives notification
        NotificationEntry.insert user_id, @summary1, reason: "assign"
        NotificationEntry.insert user_id, @summary2, reason: "invitation"

        NotificationEntry.insert @user2.id, @summary3

        # Because we are focused, the query includes the current user as an author filter
        # If we add an additional author filter, it will be appended to the query via an 'AND'
        # This means we should always end up with an empty result set
        results = NotificationEntry.for_user_with_options(user_id, focusing: user_id, authors: [@user2])
        assert_equal [], results.map(&:summary_id)
      end

      test "for_user_with_options for team_mentioned reason with reason override" do
        user_id = @summary1.thread_author_id
        # @summary1 has same author as user who receives notification
        NotificationEntry.insert user_id, @summary1, reason: "assign"
        NotificationEntry.insert user_id, @summary2, reason: "team_mention"

        # Because the team_mention view is active, the query includes the team_mention reason
        # If we add an additional reason filter, it will be appended to the query via an 'AND'
        # This means we should always end up with an empty result set
        results = NotificationEntry.for_user_with_options(user_id, team_mention: true, reasons: "assign")
        assert_equal [], results.map(&:summary_id)
      end

      test "for_user_with_options for client_apps_important reason" do
        user_id = @user.id

        valid_reasons = %w(
          assign
          author
          manual
          mention
          review_requested
        )

        invalid_reasons = %w(
          subscribed
          invitation
          state_change
          team_mention
          ci_activity
          comment
          invitation
          security_advisory_credit
          member_feature_requested
        )

        reasons = valid_reasons + invalid_reasons

        # Ensure that the user is starting with a clean inbox w/o filters
        assert_empty NotificationEntry.for_user(user_id)

        repo = create(:repository, owner: @user, id: 42, from_example: :pull_request_source)
        newsies_list = Newsies::List.to_object(repo)

        reasons.each do |r|
          notification_thread = create(:issue, repository: repo)
          comment = create(:issue_comment, issue: notification_thread)
          newsies_thread = Newsies::Thread.to_object(notification_thread, list: newsies_list)
          summary = NotificationSummary.fetch_and_update!(repo, notification_thread, comment)

          NotificationEntry.insert user_id, summary, reason: r
        end

        # Ensure that we have inserted notifications for all reasons before checking filter results
        all_notification_reasons = NotificationEntry.for_user_with_options(user_id).map(&:reason)
        assert_same_elements reasons, all_notification_reasons

        # Ensure that only the valid reasons are returned when filtering by important
        results = NotificationEntry.for_user_with_options(user_id, client_apps_important: true)
        assert_same_elements valid_reasons, results.map(&:reason)
      end
    end

    context ".count" do
      test "counts" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        assert_equal 2, NotificationEntry.count(@user.id)
      end

      test "counts unread" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.mark_summary :read, @user.id, @summary2.id
        assert_equal 1, NotificationEntry.count(@user.id, unread: true)
      end

      test "counts read" do
        NotificationEntry.insert @user.id, @summary1
        assert_equal 0, NotificationEntry.count(@user.id, read: true)

        NotificationEntry.mark_summary :read, @user.id, @summary1.id
        assert_equal 1, NotificationEntry.count(@user.id, read: true)
      end

      test "count above limit" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, @summary3
        result = NotificationEntry.count(@user.id, count_limit: 2)

        refute result.accurate?
        assert_equal 2, result.count
      end

      test "count at limit" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, @summary3
        result = NotificationEntry.count(@user.id, count_limit: 3)

        assert result.accurate?
        assert_equal 3, result.count
      end

      test "filters by list and thread" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, @summary3

        assert_equal 2, NotificationEntry.count(@user.id, list: @list, thread_type: "Issue")
        assert_equal 1, NotificationEntry.count(@user.id, list: @list2, thread_type: "Issue")
      end
    end

    context ".exist?" do
      test "returns true if the user has any notifications matching query" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user2.id, @summary2

        NotificationEntry.mark_summary(:read, @user.id, @summary1.id)

        assert NotificationEntry.exist?(@user.id)
        refute NotificationEntry.exist?(@user.id, unread: true)
      end
    end

    context ".counts_by_list" do
      test "returns count and unread count by list" do
        team_list = Team.new.tap { |team| team.id = 10 }
        discussion_post = DiscussionPost.new.tap { |discussion_post| discussion_post.id = 11 }
        discussion_post_summary = NotificationSummary.fetch_and_update!(team_list, discussion_post, nil)

        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, @summary3
        NotificationEntry.insert @user.id, discussion_post_summary

        # Mark summary 1 and 3 as read
        NotificationEntry.mark_summaries(:read, @user.id, [@summary1, @summary3])

        counts = NotificationEntry.counts_by_list(@user.id).sort_by(&:first)

        assert_equal 3, counts.size
        assert_equal ["Repository", @list.id, 2, 1], counts.first
        assert_equal ["Repository", @list2.id, 1, 0], counts.second
        assert_equal ["Team", team_list.id, 1, 1], counts.third
      end

      test "empty list count" do
        assert_equal [], NotificationEntry.counts_by_list(@user.id)
      end

      test "applies a hard limit when counting notifications" do
        team_list = Team.new.tap { |team| team.id = 10 }
        discussion_post = DiscussionPost.new.tap { |post| post.id = 11 }
        discussion_post_summary = NotificationSummary.fetch_and_update!(team_list, discussion_post, nil)

        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, @summary3
        NotificationEntry.insert @user.id, discussion_post_summary
        counts = NotificationEntry.stub_const(:COUNT_BY_LIST_LIMIT, 2) do
          NotificationEntry.counts_by_list(@user.id).sort_by(&:first)
        end

        # make sure we are missing the notification for the team
        assert_equal 2, counts.size
        assert_equal ["Repository", @list.id, 2, 2], counts.first
        assert_equal ["Repository", @list2.id, 1, 1], counts.second
      end
    end

    context ".mark_all" do
      test "marks summaries for a user" do
        team_list = Team.new.tap { |team| team.id = 10 }
        newsies_team_list = Newsies::List.to_object(team_list)

        discussion_post_thread = DiscussionPost.new.tap { |discussion_post| discussion_post.id = 11 }
        discussion_post_summary = NotificationSummary.fetch_and_update!(team_list, discussion_post_thread, nil)
        discussion_post_thread_key = NotificationEntry.to_thread_key(team_list, discussion_post_thread)
        discussion_post_newsies_thread = Newsies::Thread.to_object(discussion_post_thread, list: newsies_team_list)

        @other_user = Struct.new(:id).new(@user.id + 100)
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.insert @user.id, discussion_post_summary
        NotificationEntry.insert T.unsafe(@other_user).id, @summary2

        # not marked as read as updated_at after mark_all time
        Timecop.travel(30.seconds) do
          NotificationEntry.insert @user.id, @summary1
        end

        assert(
          NotificationEntry
            .for_user_and_threads(@user.id, [@newsies_thread1, @newsies_thread2, discussion_post_newsies_thread])
            .all? { |s| s.unread? })
        assert NotificationEntry.for_user_and_threads(T.unsafe(@other_user).id, [@newsies_thread2])
          .all? { |s| s.unread? }

        NotificationEntry.mark_all Time.now + 1, @user.id

        assert(
          NotificationEntry
            .for_user_and_threads(@user.id, [@newsies_thread2, discussion_post_newsies_thread])
            .all? { |s| !s.unread? && !s.last_read_at.nil? })
        assert NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).all? { |s| s.unread? && s.last_read_at.nil? }
        assert NotificationEntry.for_user_and_threads(T.unsafe(@other_user).id, [@newsies_thread2])
          .all? { |s| s.unread? }
      end

      test "marks summaries for a user and list" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary3

        assert NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1, @newsies_thread3]).all? { |s| s.unread? }

        newsies_list = Newsies::List.to_object(@list2)
        NotificationEntry.mark_all Time.now + 1, @user.id, newsies_list

        assert NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).all? { |s| s.unread? && s.last_read_at.nil? }
        assert NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread3]).all? { |s| !s.unread? && !s.last_read_at.nil? }
      end

      test "marks summaries for a user and team list" do
        team_list = Team.new.tap { |team| team.id = 10 }
        newsies_team_list = Newsies::List.to_object(team_list)

        discussion_post_thread = DiscussionPost.new.tap { |discussion_post| discussion_post.id = 11 }
        discussion_post_summary = NotificationSummary.fetch_and_update!(team_list, discussion_post_thread, nil)
        discussion_post_thread_key = NotificationEntry.to_thread_key(team_list, discussion_post_thread)
        discussion_post_newsies_thread = Newsies::Thread.to_object(discussion_post_thread, list: newsies_team_list)

        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary3
        NotificationEntry.insert @user.id, discussion_post_summary
        assert(
          NotificationEntry
            .for_user_and_threads(@user.id, [@newsies_thread1, @newsies_thread3, discussion_post_newsies_thread])
            .all? { |s| s.unread? })

        newsies_list = Newsies::List.to_object(team_list)
        NotificationEntry.mark_all Time.now + 1, @user.id, newsies_list

        assert(
          NotificationEntry
            .for_user_and_threads(@user.id, [@newsies_thread1, @newsies_thread3])
            .all? { |s| s.unread? && s.last_read_at.nil? })
        assert(
          NotificationEntry
            .for_user_and_threads(@user.id, [discussion_post_newsies_thread])
            .all? { |s| !s.unread? && !s.last_read_at.nil? },
          NotificationEntry.for_user_and_threads(@user.id, [discussion_post_newsies_thread]).inspect)
      end
    end

    context ".mark_scope" do
      test "marks everything in a scope as read" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.update_all(unread: :inbox_unread)

        assert_empty NotificationEntry.for_user(@user.id).read

        time = Time.now + 1
        NotificationEntry.mark_scope_as(:read, NotificationEntry.for_user(@user.id), time)

        refute_empty NotificationEntry.for_user(@user.id).read
      end

      test "marks everything in a scope as unread" do
        time = Time.now + 1
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.update_all(unread: :inbox_read, last_read_at: time)

        assert_empty NotificationEntry.for_user(@user.id).unread

        NotificationEntry.mark_scope_as(:unread, NotificationEntry.for_user(@user.id), time)

        refute_empty NotificationEntry.for_user(@user.id).unread
      end

      test "marks everything in a scope as archived" do
        NotificationEntry.insert @user.id, @summary1
        NotificationEntry.insert @user.id, @summary2
        NotificationEntry.update_all(unread: :inbox_unread)

        assert_empty NotificationEntry.for_user(@user.id).where(status: :archived)

        time = Time.now + 1
        NotificationEntry.mark_scope_as(:archived, NotificationEntry.for_user(@user.id), time)

        refute_empty NotificationEntry.for_user(@user.id).where(status: :archived)
      end

      test "raises an error for an unknown state" do
        assert_raises ArgumentError do
          NotificationEntry.mark_scope_as(:tacos, NotificationEntry.all)
        end
      end
    end

    context ".for_user_and_threads" do
      test "for_user_and_threads returns rows in same order" do
        non_existent_newsies_thread = Newsies::Thread.new("Issue", 0, list: @newsies_list)
        NotificationEntry.insert @user.id, @summary1, reason: :a
        NotificationEntry.insert @user.id, @summary2, reason: :b
        NotificationEntry.insert @user.id, @summary3, reason: :c

        results = NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1, @newsies_thread2, non_existent_newsies_thread, @newsies_thread3])
        assert_equal [@summary1.id, @summary2.id, @summary3.id], results.map(&:summary_id)
      end

      test "empty for_user_and_threads" do
        assert_equal 0, NotificationEntry.count(@user.id)
        assert_equal [], NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1])
      end
    end

    context "unread_before" do
      test "returns unread notifications that where updated before the given time" do
        @other_user = Struct.new(:id).new(@user.id + 100)
        NotificationEntry.insert @user.id, @summary1
        unread_notification1 = NotificationEntry.last
        NotificationEntry.insert @user.id, @summary3
        unread_notification2 = NotificationEntry.last
        NotificationEntry.insert T.unsafe(@other_user).id, @summary1
        Timecop.travel(30.seconds) do
          NotificationEntry.insert @user.id, @summary2
        end

        expected = [unread_notification1, unread_notification2]
        assert_equal expected, NotificationEntry.unread_before(Time.now + 1, @user.id)

        newsies_list = Newsies::List.to_object(@list)
        assert_equal [unread_notification1], NotificationEntry.unread_before(Time.now + 1, @user.id, newsies_list)
      end
    end

    test "inserts mentioned summary" do
      NotificationEntry.insert @user.id, @summary1, reason: :mention
      NotificationEntry.insert @user.id, @summary2

      assert_equal 2, NotificationEntry.count(@user.id)
      assert_equal 1, NotificationEntry.count(@user.id, participating: true)

      results = NotificationEntry.for_user_with_options(@user.id, participating: true)
      assert_equal [@summary1.id], results.map(&:summary_id)
    end

    test "inserts summary" do
      NotificationEntry.insert @user.id, @summary1

      assert_equal 1, NotificationEntry.count(@user.id)

      entry = NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).first
      assert_equal @summary1.id, entry.summary_id
      assert_predicate entry, :unread?
      assert_equal "", entry.reason
      assert !entry.mentioned
    end

    test "inserts summary with reason" do
      NotificationEntry.insert @user.id, @summary1, reason: :foo

      entry = NotificationEntry.for_user_and_threads(@user.id, [@newsies_thread1]).first

      assert_equal @summary1.id, entry.summary_id
      assert_equal "foo", entry.reason
    end

    context "#to_summary_hash" do
      test "is nil if rollup summary has been deleted" do
        NotificationEntry.insert(@user.id, @summary1)

        @summary1.delete

        assert_nil NotificationEntry.last!.to_summary_hash
      end

      test "includes the notification_summary's summary_hash data" do
        NotificationEntry.insert(@user.id, @summary1)
        notification_entry = NotificationEntry.last!
        rollup_summary_hash = notification_entry.notification_summary&.to_summary_hash

        summary_hash = notification_entry.to_summary_hash

        assert_equal rollup_summary_hash, summary_hash.slice(*rollup_summary_hash.keys)
      end

      test "has default data from the notification entry" do
        NotificationEntry.insert(@user.id, @summary1, reason: "manual")
        notification_entry = NotificationEntry.last!

        summary_hash = notification_entry.to_summary_hash

        assert summary_hash[:unread]
        assert_equal "manual", summary_hash[:reason]
        refute summary_hash[:mentioned]
        assert_nil summary_hash[:last_read_at]
        assert_equal notification_entry.updated_at, summary_hash[:last_updated_at]
        assert_equal notification_entry.id, summary_hash[:notification_entry_id]
      end

      test "is read if notification entry is read" do
        read_at = Time.parse("2019-04-25T15:12:11Z")

        Timecop.freeze(read_at) do
          NotificationEntry.insert(@user.id, @summary1)
          NotificationEntry.mark_summary(:read, @user.id, @summary1)

          notification_entry = NotificationEntry.last!

          summary_hash = notification_entry.to_summary_hash

          refute summary_hash[:unread]
          assert_equal read_at, summary_hash[:last_read_at]
        end
      end

      test "is mentioned if reason is mention" do
        NotificationEntry.insert(@user.id, @summary1, reason: "mention")
        notification_entry = NotificationEntry.last!

        summary_hash = notification_entry.to_summary_hash

        assert summary_hash[:mentioned]
      end
    end

    context "#newsies_thread" do
      test "returns the newsies thread" do
        NotificationEntry.insert @user.id, @summary1

        notification_entry = NotificationEntry.for_user_with_options(@user.id).first
        assert_equal \
          Newsies::Thread.new(@thread1.class.name, @thread1.id.to_s, list: Newsies::List.to_object(@list)),
          notification_entry.newsies_thread
      end
    end

    context "#newsies_list" do
      test "returns the newsies thread" do
        NotificationEntry.insert @user.id, @summary1

        notification_entry = NotificationEntry.for_user_with_options(@user.id).first
        assert_equal Newsies::List.to_object(@list), notification_entry.newsies_list
      end
    end

    test "insert" do
      assert_equal [], NotificationEntry.for_user_with_options(@user.id)

      NotificationEntry.insert @user.id, @summary1

      results = NotificationEntry.for_user_with_options(@user.id)
      assert result = results.first
      assert_equal @summary1.id, result.summary_id
      assert_predicate result, :unread?
      assert_equal "", result.reason
      assert !result.mentioned
      assert !result.last_read_at
    end

    test "insert with reason" do
      assert_equal [], NotificationEntry.for_user_with_options(@user.id)

      NotificationEntry.insert @user.id, @summary1, reason: :foo

      results = NotificationEntry.for_user_with_options(@user.id)
      assert result = results.first
      assert_equal @summary1.id, result.summary_id
      assert_predicate result, :unread?
      assert_equal "foo", result.reason
      assert !result.mentioned
      assert !result.last_read_at
    end
  end
end
