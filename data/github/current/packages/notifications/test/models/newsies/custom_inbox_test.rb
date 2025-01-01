# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

module Newsies
  class CustomInboxTest < GitHub::TestCase
    fixtures do
      @user = create(:user)
      @inboxes = create_list(:custom_inbox, 2, user: @user)

      @repo1 = create(:repository)
      @repo2 = create(:repository)
    end

    context "validations" do
      test "prevents a user from creating more than the maximum allowed number of inboxes" do
        inbox = build(:custom_inbox, user: @user)

        CustomInbox.stub_const(:MAX_INBOXES_PER_USER, 2) do
          refute inbox.save
          assert_equal(
            "User has reached maximum number of allowed inboxes",
            inbox.errors.full_messages.to_sentence,
          )
        end
      end

      test "prevents a user from creating more than one inbox with the same name" do
        inbox = build(:custom_inbox, user: @user, name: @inboxes.first.name)

        refute inbox.save
        assert_equal "Name has already been taken", inbox.errors.full_messages.to_sentence
      end

      test "validates name length in bytes" do
        # 350 chars, but 1050 bytes
        test_name = "’" * 350

        inbox = build(:custom_inbox, name: test_name)
        refute inbox.save
        assert_equal "Name is too long (maximum is 256 characters)", inbox.errors.full_messages.to_sentence
      end

      test "validates query_string length in bytes" do
        # 350 chars, but 1050 bytes
        test_name = "’" * 350

        inbox = build(:custom_inbox, query_string: test_name)
        refute inbox.save
        assert_equal "Query string is too long (maximum is 256 characters)", inbox.errors.full_messages.to_sentence
      end
    end


    context ".default_filters" do
      test "returns the default inboxes as read only Newsies::CustomInbox objects" do
        default_filters = CustomInbox.default_filters(@user)

        default_filters.each do |default_inbox|
          assert default_inbox.is_a?(Newsies::CustomInbox)
          assert default_inbox.readonly?
        end
      end

      test "sets default_filter to true" do
        default_filters = CustomInbox.default_filters(@user)

        default_filters.each do |default_inbox|
          assert default_inbox.default_filter?
        end
      end
    end

    context "#global_id" do
      test "returns default_filter_id if object is a default filter" do
        inbox = CustomInbox.new(
          default_filter_id: "assigned",
          name: "🎯 Assigned",
          query_string: "reason:assign",
          user_id: @user.id,
          default_filter: true,
        )

        assert_equal "assigned", inbox.global_id
      end

      test "returns super if object is not a default filter" do
        assert_equal @inboxes.first.id, @inboxes.first.global_id
      end
    end

    context "#default_filter?" do
      test "returns false if default_filter is not set" do
        refute @inboxes.first.default_filter?
      end

      test "returns the value of default_filter if set" do
        default_inbox = CustomInbox.new(
          default_filter_id: "assigned",
          name: "🎯 Assigned",
          query_string: "reason:assign",
          user_id: @user.id,
          default_filter: true,
        )

        assert default_inbox.default_filter?
      end
    end

    context "#readable_by?" do
      test "returns true when the user is the owner of the custom inbox" do
        assert @inboxes.first.readable_by?(@user)
      end

      test "returns false when the user is not the owner of the custom inbox" do
        rando = create(:user)
        refute @inboxes.first.readable_by?(rando)
      end
    end

    context "#async_batch_unread_count" do
      test "returns 0 with no notifications" do
        inbox = create(:custom_inbox, user: @user, query_string: "is:issue")

        assert_equal 0, inbox.async_batch_unread_count.sync
      end

      test "returns 0 if query specifies a status that does not include unread" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")

        inbox = create(:custom_inbox, user: @user, query_string: "is:issue is:read")
        assert_equal 0, inbox.async_batch_unread_count.sync
      end

      test "returns 0 if query specifies saved notifications" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")

        inbox = create(:custom_inbox, user: @user, query_string: "is:saved")
        assert_equal 0, inbox.async_batch_unread_count.sync
      end

      test "returns the count of matching unread notifications by thread type" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 3, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Release;3")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 4, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;3")

        inbox = create(:custom_inbox, user: @user, query_string: "is:issue")
        assert_equal 2, inbox.async_batch_unread_count.sync

        inbox = create(:custom_inbox, user: @user, query_string: "is:release")
        assert_equal 1, inbox.async_batch_unread_count.sync
      end

      test "returns count of 0 if thread type filter is provided but thread type doesn't exist" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 3, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Release;3")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 4, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;3")

        inbox = create(:custom_inbox, user: @user, query_string: "is:issue")
        assert_equal 2, inbox.async_batch_unread_count.sync

        inbox = create(:custom_inbox, user: @user, query_string: "is:random-string")
        assert_equal 0, inbox.async_batch_unread_count.sync
      end

      test "returns the count of matching unread notifications by list" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 3, list_type: "Repository", list_id: @repo2.id, thread_key: "#{@repo2.id};Issue;3")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 4, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;4")

        inbox = create(:custom_inbox, user: @user, query_string: "repo:#{@repo1.nwo}")
        assert_equal 2, inbox.async_batch_unread_count.sync

        inbox = create(:custom_inbox, user: @user, query_string: "repo:#{@repo2.nwo}")
        assert_equal 1, inbox.async_batch_unread_count.sync
      end

      test "returns the count of matching unread notifications by reason" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, reason: "mention", summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, reason: "mention", summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, reason: "assign", summary_id: 3, list_type: "Repository", list_id: @repo2.id, thread_key: "#{@repo2.id};Issue;3")
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, reason: "mention", summary_id: 4, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;4")

        inbox = create(:custom_inbox, user: @user, query_string: "reason:mention")
        assert_equal 2, inbox.async_batch_unread_count.sync

        inbox = create(:custom_inbox, user: @user, query_string: "reason:assign")
        assert_equal 1, inbox.async_batch_unread_count.sync
      end

      test "returns the count of matching unread notifications by org" do
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1", owner_id: @repo1.owner_id)
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 2, list_type: "Repository", list_id: @repo2.id, thread_key: "#{@repo2.id};Issue;2", owner_id: @repo2.owner_id)
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 3, list_type: "Repository", list_id: @repo2.id, thread_key: "#{@repo2.id};Issue;3", owner_id: @repo2.owner_id)

        inbox = create(:custom_inbox, user: @user, query_string: "org:#{@repo1.owner.login}")
        assert_equal 1, inbox.async_batch_unread_count.sync

        inbox = create(:custom_inbox, user: @user, query_string: "org:#{@repo2.owner.login}")
        assert_equal 1, inbox.async_batch_unread_count.sync
      end

      test "returns the count of matching unread notifications by author" do
        author1 = create(:user)
        author2 = create(:user)

        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1", author_id: author1.id)
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 1, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2", author_id: author2.id)
        Newsies::NotificationEntry.create(user_id: @user.id, unread: 0, summary_id: 3, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;3", author_id: author2.id)

        inbox = create(:custom_inbox, user: @user, query_string: "author:#{author1.login}")
        assert_equal 1, inbox.async_batch_unread_count.sync

        inbox = create(:custom_inbox, user: @user, query_string: "author:#{author2.login}")
        assert_equal 1, inbox.async_batch_unread_count.sync
      end

      test "behaves efficiently when used via GitHub::PrefillAssociations.prefill_batch_method" do
        recipients = create_list(:user, 2)
        recipients.each do |r|
          Newsies::NotificationEntry.create(user_id: r.id, unread: 1, summary_id: 1, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;1")
          Newsies::NotificationEntry.create(user_id: r.id, unread: 1, summary_id: 2, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;2")
          Newsies::NotificationEntry.create(user_id: r.id, unread: 0, summary_id: 3, list_type: "Repository", list_id: @repo1.id, thread_key: "#{@repo1.id};Issue;3")
        end
        inboxes = recipients.map { |r| create(:custom_inbox, user: r, query_string: "is:unread") }

        assert_max_query_count_per_table({ users: 1, notification_entries: 4 }) do
          GitHub::PrefillAssociations.prefill_batch_method(inboxes, :unread_count)
          assert_equal 2, inboxes[0].unread_count
          assert_equal 2, inboxes[1].unread_count
        end
      end
    end
  end
end
