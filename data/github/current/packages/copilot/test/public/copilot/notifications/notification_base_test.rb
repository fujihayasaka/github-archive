# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotNotificationsNotificationBaseTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
  end

  test "initialize creates copilot user" do
    base = Copilot::Notifications::NotificationBase.new(@user)
    assert base.copilot_user.is_a?(Copilot::User)

    base = Copilot::Notifications::NotificationBase.new(Copilot::User.new(@user))
    assert base.copilot_user.is_a?(Copilot::User)
  end
end if GitHub.copilot_enabled?
