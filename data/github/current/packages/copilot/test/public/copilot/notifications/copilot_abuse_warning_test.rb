# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Notifications::CopilotAbuseWarningTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @seat = create(:copilot_seat)
    @user = @seat.assigned_user
    Copilot::User.new(@user).warn_user!(create(:user), "123")
    @org = @seat.organization
  end

  test "does not send notification if there is no warning" do
    notification = Copilot::Notifications::CopilotAbuseWarning.new(create(:user))
    refute notification.send_condition
  end

  test "does not send a notification if the user is blocked but not warned" do
    user = create(:user)
    Copilot::User.new(user).administrative_block!(create(:user))
    notification = Copilot::Notifications::CopilotAbuseWarning.new(Copilot::User.new(user))
    refute notification.send_condition
  end

  test "sends a notification if there is an active warning" do
    notification = Copilot::Notifications::CopilotAbuseWarning.new(Copilot::User.new(@user))
    assert notification.send_condition
  end

  test "only sends a notification for the first time" do
    notification = Copilot::Notifications::CopilotAbuseWarning.new(Copilot::User.new(@user))
    assert notification.send_condition
    refute notification.existing?
    notification.store

    notification = Copilot::Notifications::CopilotAbuseWarning.new(Copilot::User.new(@user))
    refute(notification.send_condition, "send_notification should be false as it's existing")
  end
end if GitHub.copilot_enabled?
