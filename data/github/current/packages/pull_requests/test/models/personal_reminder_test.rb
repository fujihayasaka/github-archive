# typed: false
# frozen_string_literal: true

require "test_helper"

class PersonalReminderTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    @org = create(:business_plus_organization)
  end

  context "validations" do
    test "user must be present" do
      personal_reminder = build(:personal_reminder, user: nil)

      refute personal_reminder.valid?
      assert_equal ["can't be blank"], personal_reminder.errors[:user]
    end

    test "Ensures workspace is part of authorized workspaces" do
      enable_feature_flag(:scheduled_reminders_ms_teams, @org)
      teams_workspace = create(:reminder_teams_workspace, remindable: @org, teams_id: ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID)
      personal_reminder = build(:personal_reminder, remindable: @org, slack_workspace: teams_workspace, user: @user)

      assert personal_reminder.valid?
    end
  end

  context "#remindable" do
    test "must be present" do
      personal_reminder = build(:personal_reminder)
      personal_reminder.remindable = nil

      refute personal_reminder.valid?
      assert_equal ["can't be blank"], personal_reminder.errors[:remindable]
    end

    test "supports private repos" do
      reminder = build(:personal_reminder, remindable: @org)
      assert_predicate reminder, :supports_private_repos?
    end

    test "nil remindable doesnt support private repos" do
      reminder = build(:personal_reminder, remindable: @org)
      reminder.remindable = nil

      refute_predicate reminder, :supports_private_repos?
    end

    test "doesn't support private repos" do
      free_org = create(:organization, admin: @user, plan: "free")
      reminder = build(:personal_reminder, remindable: free_org)
      refute_predicate reminder, :supports_private_repos?
    end
  end

  context "#slack_workspace" do
    test "must belongs to same organization" do
      slack_workspace_from_another_org = create(:reminder_slack_workspace, remindable: create(:organization))
      personal_reminder = build(:personal_reminder, remindable: create(:organization), slack_workspace: slack_workspace_from_another_org)

      refute personal_reminder.valid?
      assert_equal ["can't be blank"], personal_reminder.errors[:slack_workspace]
      assert_nil personal_reminder.slack_workspace
    end

    test "not valid when user isn't a member" do
      personal_reminder = build(:personal_reminder)
      personal_reminder.slack_workspace.reminder_slack_workspace_memberships.destroy_all

      refute personal_reminder.valid?
      assert_equal ["can't be blank"], personal_reminder.errors[:slack_workspace]
    end
  end

  context "#teams_workspace" do
    test "can be configured for personal_reminder" do
      teams_workspace = create(:reminder_teams_workspace, remindable: @org, teams_id: ReminderTeamsWorkspace::PERSONAL_REMINDER_TEAMS_ID)
      personal_reminder = build(:personal_reminder, remindable: @org, slack_workspace: teams_workspace, user: @user)

      assert_predicate personal_reminder, :valid?
      assert_equal personal_reminder.slack_workspace, teams_workspace
    end
  end

  context "event_types" do
    test "builds event subscription objects" do
      reminder = build(:personal_reminder)
      event_subscriptions_attributes = [
        { "event_type" => "pull_request_opened" },
        { "event_type" => "pull_request_merged" },
      ]

      reminder.assign_attributes(event_subscriptions_attributes: event_subscriptions_attributes)
      reminder.save!
      assert_equal %w[pull_request_opened pull_request_merged], reminder.reload.event_subscriptions.map(&:event_type)
    end

    test "deletes old event subscription" do
      reminder = create(:personal_reminder, event_types: %w[pull_request_opened pull_request_merged])
      previous_event_subscriptions = reminder.event_subscriptions.to_a

      reminder.assign_attributes(event_subscriptions_attributes: [])
      reminder.save!

      assert_equal([], reminder.event_subscriptions.map(&:event_type))

      previous_event_subscriptions.each do |previous_event_sub|
        assert_raises(ActiveRecord::RecordNotFound) { previous_event_sub.reload }
      end
    end

    test "replaces existing event subscriptions" do
      reminder = create(:personal_reminder, event_types: %w[check_failure comment_reply])
      original_event_subs = reminder.event_subscriptions.to_a

      event_subscriptions_attributes = [{ "event_type" => "pull_request_opened" }, { "event_type" => "pull_request_merged" }]
      reminder.assign_attributes(event_subscriptions_attributes: event_subscriptions_attributes)
      reminder.save!

      assert_same_elements(%w[pull_request_opened pull_request_merged], reminder.reload.event_subscriptions.map(&:event_type))
    end

    test "adds new subscriptions" do
      reminder = create(:personal_reminder, event_types: %w[pull_request_opened pull_request_merged])

      previous_event_subscriptions = reminder.event_subscriptions.to_a
      assert_equal 2, previous_event_subscriptions.size
      reminder.assign_attributes(event_subscriptions_attributes: [
        { "event_type" => "pull_request_opened" },
        { "event_type" => "pull_request_merged" },
        { "event_type" => "check_failure" },
      ])
      reminder.save!

      assert_same_elements(%w[pull_request_opened pull_request_merged check_failure], reminder.reload.event_subscriptions.map(&:event_type))
    end
  end

  context "delivery_times_attributes" do
    test "builds delivery time objects, removing existing delivery times" do
      reminder = build(:personal_reminder)
      assert_equal 1, reminder.delivery_times.size
      assert_equal "Monday", reminder.delivery_times.first.day
      assert_equal "9:00 AM", reminder.delivery_times.first.time

      delivery_times_attributes = [
        { "day" => "Tuesday", "time" => "9:00 AM" },
        { "day" => "Friday", "time" => "9:00 AM" },
      ]

      reminder.assign_attributes(delivery_times_attributes: delivery_times_attributes)
      reminder.save!

      actual_attributes = reminder.delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }

      assert_equal delivery_times_attributes, actual_attributes
    end

    test "deletes old delivery times" do
      reminder = create(:personal_reminder, days: ["Monday"], times: ["10:00 AM"])
      previous_delivery_times = reminder.delivery_times.to_a

      delivery_times_attributes = [
        { "day" => "Friday", "time" => "9:00 AM" },
      ]

      reminder.assign_attributes(delivery_times_attributes: delivery_times_attributes)
      reminder.save!

      actual_attributes = reminder.delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }
      assert_equal delivery_times_attributes, actual_attributes

      previous_delivery_times.each do |previous_delivery_time|
        assert_raises(ActiveRecord::RecordNotFound) { previous_delivery_time.reload }
      end
    end

    test "replaces existing delivery times" do
      reminder = create(:personal_reminder, remindable: @org, days: %w[Monday Friday])

      delivery_times_attributes = [{ "day" => "Wednesday", "time" => "12:00 PM" }]
      reminder.assign_attributes(delivery_times_attributes: delivery_times_attributes)
      reminder.save!

      actual_attributes = reminder.delivery_times.map { |delivery_time| delivery_time.slice("day", "time") }
      assert_equal delivery_times_attributes, actual_attributes
    end

    test "deletes previous delivery times" do
      reminder = create(:personal_reminder, remindable: @org, days: %w[Monday Friday])

      previous_delivery_times = reminder.delivery_times.to_a
      reminder.assign_attributes(delivery_times_attributes: [{ "day" => "Wednesday", "time" => "12:00 PM" }])
      reminder.save!

      previous_delivery_times.each do |previous_delivery_time|
        assert_raises(ActiveRecord::RecordNotFound) { previous_delivery_time.reload }
      end
    end

    test "reuses existing delivery times" do
      reminder = create(:personal_reminder, remindable: @org, days: ["Monday"], times: ["12:00 PM"])

      previous_delivery_times = reminder.delivery_times.to_a
      assert_equal 1, previous_delivery_times.size
      reminder.assign_attributes(delivery_times_attributes: [{ "day" => reminder.delivery_times.first.day, "time" => reminder.delivery_times.first.time }])
      reminder.save!

      assert_same_elements(previous_delivery_times, reminder.reload.delivery_times)
    end
  end

  context "#accessible_repository_ids" do
    test "returns organization repository IDs that the user has access to" do
      org_repo          = create(:repository, owner: @org)
      private_org_repo  = create(:private_repository, owner: @org)
      user_repo         = create(:repository, owner: @user)
      personal_reminder = create(:personal_reminder, remindable: @org, user: @user)

      @org.add_member(@user, action: :write)
      assert_equal [org_repo.id, private_org_repo.id], personal_reminder.accessible_repository_ids
    end

    test "returns organization repository ID, without private repos, that the user has access to when a free org" do
      org_repo          = create(:repository, owner: @org)
      private_org_repo  = create(:private_repository, owner: @org)
      user_repo         = create(:repository, owner: @user)
      personal_reminder = create(:personal_reminder, remindable: @org, user: @user)

      @org.add_member(@user, action: :write)
      @org.plan = "free"
      @org.save

      personal_reminder.reset_memoized_attributes
      assert_equal [org_repo.id], personal_reminder.accessible_repository_ids
    end

    test "returns an empty array when user not a member of the remindable organization" do
      org_repo          = create(:repository, owner: @org)
      user_repo         = create(:repository, owner: @user)
      personal_reminder = create(:personal_reminder, remindable: @org, user: @user)

      assert_equal [], personal_reminder.accessible_repository_ids
    end
  end

  context ".listener_ids_for" do
    test "returns list of user IDs subscribed to a given event" do
      users = 3.times.map { create(:user) }

      create(:personal_reminder, remindable: @org, user: users[0], event_types: [:merge_conflict])
      create(:personal_reminder, remindable: @org, user: users[1], event_types: [:merge_conflict, :review_request])
      create(:personal_reminder, remindable: @org, user: users[2], event_types: [:merge_conflict, :review_request, :mention])

      assert_equal users.map(&:id),        PersonalReminder.listener_ids_for(@org, event_type: :merge_conflict)
      assert_equal users[1..-1].map(&:id), PersonalReminder.listener_ids_for(@org, event_type: :review_request)
      assert_equal [users.last.id],        PersonalReminder.listener_ids_for(@org, event_type: :mention)
      assert_equal [],                     PersonalReminder.listener_ids_for(@org, event_type: :assignment)
    end

    test "only returns listeners from the given organization" do
      org2 = create(:business_plus_organization)
      user2 = create(:user)

      create(:personal_reminder, remindable: @org, user: @user, event_types: [:merge_conflict])
      create(:personal_reminder, remindable: org2, user: user2, event_types: [:merge_conflict])

      assert_equal [@user.id], PersonalReminder.listener_ids_for(@org, event_type: :merge_conflict)
    end

    test "returns empty list when given invalid event" do
      assert_equal [], PersonalReminder.listener_ids_for(@org, event_type: :foo)
    end
  end

  test "#flipper_id" do
    reminder = create(:personal_reminder, remindable: @org, user: @user)

    assert_equal "PersonalReminder:#{reminder.id}", reminder.flipper_id
  end
end
