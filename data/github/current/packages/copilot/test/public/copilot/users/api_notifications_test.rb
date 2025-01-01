# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersApiNotificationsTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  include DogstatsTestHelpers

  fixtures do
    @user = create(:user)
  end

  context "check_notifications" do
    test "handles an error" do
      Failbot.expects(:report).with(instance_of(StandardError), notification_id: "subscription_ending")
      Copilot::Notifications::SubscriptionEnding.any_instance.stubs(:send_condition).raises(StandardError)
      assert_nothing_raised do
        Copilot::User.new(@user).check_notifications
      end
    end

    test "calls all" do
      # TODO: test something
      Copilot::User.new(@user).check_notifications
    end

    test "An enterprise team user shouldn't error" do
      seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
      seat_assignment.convert_to_seats

      seat = seat_assignment.seats.first
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)

      assert_nothing_raised do
        copilot_user.check_notifications
      end
    end

  end

  context "acknowledges notification" do
    test "acknowledges a seat added notification" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)
      notification = Copilot::Notifications::CopilotSeatAdded.new(copilot_user)
      assert notification.send_condition
      assert_equal "The organization #{seat.organization.name} has granted you access to GitHub Copilot.", notification.message
    end

    test "does not send the high-cardinality notification_id tag to Datadog" do
      seat = create(:copilot_seat)
      user = seat.assigned_user
      copilot_user = Copilot::User.new(user)
      notification = Copilot::Notifications::CopilotSeatAdded.new(copilot_user)
      assert notification.store
      assert_equal "copilot_seat_added_#{seat.id}", notification.notification_id

      assert copilot_user.acknowledge_notification(notification.notification_id)
      statsd_increment = GitHub.dogstats.increments.find { |s| s.stat == "copilot.notification" }
      assert statsd_increment.tags.to_a == ["event:acknowledged"]
    end
  end
end if GitHub.copilot_enabled?
