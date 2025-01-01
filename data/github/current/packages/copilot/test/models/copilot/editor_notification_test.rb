# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotEditorNotificationTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
  end

  test "validates" do
    editor_notification = Copilot::EditorNotification.new

    refute editor_notification.valid?
    refute_nil editor_notification.errors[:user]
    refute_nil editor_notification.errors[:notification_id]

    editor_notification.user = @user
    refute editor_notification.valid?
    refute_nil editor_notification.errors[:notification_id]

    editor_notification.notification_id = Copilot::EditorNotification::COPILOT_NOTIFICATION_TYPES.keys.first.to_s
    assert editor_notification.valid?

    Copilot::EditorNotification.create!(user: @user, notification_id: editor_notification.notification_id)

    assert_raises(ActiveRecord::RecordNotUnique) do
      editor_notification.save
    end
  end

  test ".create_for_user" do
    user = create(:user)
    notification_id = "copilot_seat_removed_123"

    freeze_time do
      assert_changes -> { Copilot::EditorNotification.count }, from: 0, to: 1 do
        Copilot::EditorNotification.create_for_user(user, notification_id, nil)
      end

      notification = Copilot::EditorNotification.last

      sleep 1
      assert_no_changes -> { Copilot::EditorNotification.count } do
        Copilot::EditorNotification.create_for_user(user, notification_id, nil)
      end

      other_notification = Copilot::EditorNotification.last
      assert_equal T.must(other_notification).user_id, T.must(notification).user_id
      refute_equal T.must(other_notification).updated_at, T.must(notification).updated_at
      assert_nil T.must(other_notification).acknowledged_at
    end
  end

  Copilot::EditorNotification::COPILOT_NOTIFICATION_TYPES.keys.map(&:to_s).each do |notification_id|
    test "scope by_type #{notification_id}" do
      editor_notification = create(:copilot_editor_notification, user: @user, notification_id: notification_id)

      assert_equal editor_notification, Copilot::EditorNotification.by_type(notification_id).first
    end
  end

  context "#friendly_name" do
    {
      "subscription_ending" => "Subscription Ending",
      "subscription_trial_ended" => "Subscription Trial Ended",
      "subscription_trial_ending" => "Subscription Trial Ending",
      "copilot_enterprise_seat_added" => "Copilot Enterprise Seat Added",
      "copilot_enterprise_seat_added_123" => "Copilot Enterprise Seat Added (Seat ID: 123)",
      "copilot_seat_added" => "Copilot Seat Added",
      "copilot_seat_added_123" => "Copilot Seat Added (Seat ID: 123)",
      "copilot_seat_removed" => "Copilot Seat Removed",
      "copilot_seat_removed_123" => "Copilot Seat Removed (Organization ID: 123)",
      "technical_preview_conversion_is_ending" => "Technical Preview Conversion Is Ending",
      "technical_preview_conversion_is_ending123" => "Technical Preview Conversion Is Ending",
      "technical_preview_conversion_starts" => "Technical Preview Conversion Starts",
      "technical_preview_converts_to_subscription" => "Technical Preview Converts to Subscription",
      "unknown_notification_type" => "Unknown Notification Type",
    }.each do |notification_id, expected_friendly_name|
      test "friendly_name for #{notification_id}" do
        editor_notification = build(
          :copilot_editor_notification,
          user: @user,
          notification_id: notification_id,
        )

        assert_equal expected_friendly_name, editor_notification.friendly_name
      end
    end

    context "friendly_name - seat_added" do
      test "gets owner of seat when owner exists" do
        seat = create(:copilot_seat)
        editor_notification = build(
          :copilot_editor_notification,
          user: seat.assigned_user,
          notification_id: "copilot_seat_added_#{seat.id}",
        )

        assert_equal "Copilot Seat Added for #{seat.owner}", editor_notification.friendly_name
      end

      test "gets owner of seat when owner is nil" do
        Copilot::Seat.any_instance.stubs(:owner).returns(nil)
        Copilot::SeatHistory.any_instance.stubs(:owner).returns(nil)
        seat = create(:copilot_seat)
        editor_notification = build(
          :copilot_editor_notification,
          user: seat.assigned_user,
          notification_id: "copilot_seat_added_#{seat.id}",
        )

        assert_equal "Copilot Seat Added (Seat ID: #{seat.id})", editor_notification.friendly_name
      end

      test "gets owner of seat history when owner is nil" do
        seat = create(:copilot_seat)
        owner = seat.owner
        Copilot::Seat.any_instance.stubs(:owner).returns(nil)
        editor_notification = build(
          :copilot_editor_notification,
          user: seat.assigned_user,
          notification_id: "copilot_seat_added_#{seat.id}",
        )

        assert_equal "Copilot Seat Added for #{owner}", editor_notification.friendly_name
      end
    end
  end

  test ".create_for_user does not create if org has opted out of communication" do
    user = create(:user)
    org = create(:copilot_for_business_enabled_organization)

    enable_feature_flag(:copilot_communication_opt_out, org)

    org.add_member(user)
    assignment = create(:copilot_seat_assignment, assignable: user, organization: org)
    assignment.convert_to_seats

    assert_no_changes -> { Copilot::EditorNotification.count } do
      Copilot::EditorNotification.create_for_user(user, "id-does-not-matter", assignment.owner)
    end
  end
end if GitHub.copilot_enabled?
