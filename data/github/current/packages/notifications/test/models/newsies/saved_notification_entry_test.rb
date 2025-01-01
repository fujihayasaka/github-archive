# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class SavedNotificationEntryTest < GitHub::TestCase
    self.strict_fixtures = false # rubocop:todo GitHub/StrictFixtures
    fixtures do
      @newsies_list = List.new("Repository", 1)
      @newsies_thread = Thread.new("Thread", 2, list: @newsies_list)
      @summary_id = 123
      @user_id = 654
    end

    context ".for_lists" do
      test "returns saved notifications for given lists" do
        repo_list_1 = Newsies::List.new("Repository", 101)
        repo_list_2 = Newsies::List.new("Repository", 102)
        team_list_1 = Newsies::List.new("Team", 101)
        team_list_2 = Newsies::List.new("Team", 102)

        threads = [
          Thread.new("Thread", 1, list: repo_list_1),
          Thread.new("Thread", 2, list: repo_list_2),
          Thread.new("Thread", 3, list: team_list_1),
          Thread.new("Thread", 4, list: team_list_2),
        ]

        SavedNotificationEntry.save(user_id: @user_id, summary_id: 10, list: threads[0].list, thread: threads[0])
        SavedNotificationEntry.save(user_id: @user_id, summary_id: 11, list: threads[1].list, thread: threads[1])
        SavedNotificationEntry.save(user_id: @user_id, summary_id: 12, list: threads[2].list, thread: threads[2])
        SavedNotificationEntry.save(user_id: @user_id, summary_id: 13, list: threads[3].list, thread: threads[3])

        assert_equal [threads[0].key], SavedNotificationEntry.for_lists([repo_list_1]).map(&:thread_key)
        assert_equal [threads[0].key, threads[1].key], SavedNotificationEntry.for_lists([repo_list_1, repo_list_2]).map(&:thread_key)
        assert_equal [threads[2].key, threads[3].key], SavedNotificationEntry.for_lists([team_list_1, team_list_2]).map(&:thread_key)

        assert_equal [threads[0].key, threads[3].key], SavedNotificationEntry.for_lists([repo_list_1, team_list_2]).map(&:thread_key)
        assert_equal [threads[0].key, threads[2].key, threads[3].key], SavedNotificationEntry.for_lists([repo_list_1, team_list_1, team_list_2]).map(&:thread_key)
      end
    end

    context ".get" do
      test "returns saved notifications if they exists" do
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: @newsies_thread)

        results = SavedNotificationEntry.get(user_id: @user_id)
        assert_equal @summary_id, results.first.summary_id
      end

      test "returns empty result if not saved notifications exist" do
        assert_empty SavedNotificationEntry.get(user_id: @user_id), "User should not have any saved notifications."
      end
    end

    context ".get_by_summary_ids" do
      test "returns saved notifications by user id and summary ids" do
        thread_3, thread_4, thread_5, thread_6 = [3, 4, 5, 6].map do |id|
          Thread.new("Thread", id, list: @newsies_list)
        end

        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: @newsies_thread)
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: thread_3)
        SavedNotificationEntry.save(user_id: @user_id, summary_id: 111, list: @newsies_list, thread: thread_4)

        # Save notifications that should not be returned
        SavedNotificationEntry.save(user_id: @user_id, summary_id: 333, list: @newsies_list, thread: thread_6)
        SavedNotificationEntry.save(user_id: 222, summary_id: @summary_id, list: @newsies_list, thread: thread_5)

        summary_ids = [@summary_id, 111]
        results = SavedNotificationEntry.get_by_summary_ids(user_id: @user_id, summary_ids: summary_ids)

        assert_equal 3, results.count
        results.each { |result| assert_includes summary_ids, result }
      end
    end

    context ".count" do
      test "counts saved notifications" do
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: @newsies_thread)
        assert_equal 1, SavedNotificationEntry.count(user_id: @user_id)

        another_list = List.new("Repository", 10)
        another_thread = Thread.new("Thread", 20, list: another_list)
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: another_list, thread: another_thread)
        assert_equal 2, SavedNotificationEntry.count(user_id: @user_id)
      end
    end

    context ".destroy" do
      test "destroys all saved notifications for the given user and list" do
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: @newsies_thread)
        refute_empty SavedNotificationEntry.get(user_id: @user_id)

        SavedNotificationEntry.destroy(user_id: @user_id, list: @newsies_list)
        assert_empty SavedNotificationEntry.get(user_id: @user_id)
      end
    end

    context ".destroy_list_set" do
      test "destroys all saved notifications of the given list" do
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: @newsies_thread)
        refute_empty SavedNotificationEntry.get(user_id: @user_id)

        SavedNotificationEntry.destroy_list_set(@newsies_list)
        assert_empty SavedNotificationEntry.get(user_id: @user_id)
      end
    end

    context ".destroy_thread_set" do
      test "destroys all saved notifications for the given thread in the given list" do
        SavedNotificationEntry.save(user_id: @user_id, summary_id: @summary_id, list: @newsies_list, thread: @newsies_thread)
        refute_empty SavedNotificationEntry.get(user_id: @user_id)

        SavedNotificationEntry.destroy_thread_set(@newsies_list, @newsies_thread)
        assert_empty SavedNotificationEntry.get(user_id: @user_id)
      end
    end

    context "#to_summary_hash" do
      test "is nil if notification summary has been deleted" do
        issue = create(:issue)
        summary = NotificationSummary.fetch_and_update!(issue.repository, issue, issue)
        newsies_list = Newsies::List.to_object(issue.repository)
        newsies_thread = Newsies::Thread.to_object(issue, list: newsies_list)
        SavedNotificationEntry.save(user_id: @user_id, summary_id: summary.id, list: newsies_list, thread: newsies_thread)

        summary.delete

        assert_nil SavedNotificationEntry.last.to_summary_hash
      end

      test "includes the notification_summary's summary_hash data" do
        issue = create(:issue)
        summary = NotificationSummary.fetch_and_update!(issue.repository, issue, issue)
        newsies_list = Newsies::List.to_object(issue.repository)
        newsies_thread = Newsies::Thread.to_object(issue, list: newsies_list)
        SavedNotificationEntry.save(user_id: @user_id, summary_id: summary.id, list: newsies_list, thread: newsies_thread)

        saved_notification_entry = SavedNotificationEntry.last
        summary_hash = saved_notification_entry.to_summary_hash
        notification_summary_hash = saved_notification_entry.notification_summary.to_summary_hash

        assert_equal notification_summary_hash, summary_hash.slice(*notification_summary_hash.keys)
      end

      test "has default data from the saved notification entry" do
        issue = create(:issue)
        summary = NotificationSummary.fetch_and_update!(issue.repository, issue, issue)
        newsies_list = Newsies::List.to_object(issue.repository)
        newsies_thread = Newsies::Thread.to_object(issue, list: newsies_list)
        SavedNotificationEntry.save(user_id: @user_id, summary_id: summary.id, list: newsies_list, thread: newsies_thread)

        saved_notification_entry = SavedNotificationEntry.last
        summary_hash = SavedNotificationEntry.last.to_summary_hash

        assert_equal true, summary_hash[:unread]
        assert_equal "saved", summary_hash[:reason]
        assert_equal false, summary_hash[:mentioned]
        assert_equal saved_notification_entry.created_at, summary_hash[:last_read_at]
      end
    end
  end
end
