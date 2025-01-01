# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Notifications::CopilotSeatRemovedTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "does not send one if no seat notification exists" do
    copilot_user = Copilot::User.new(create(:user))
    notification = Copilot::Notifications::CopilotSeatRemoved.new(copilot_user)
    refute notification.send_condition
  end

  test "sends if we directly create it" do
    user = create(:user)
    organization = create(:organization)
    organization.add_member(user)
    create(:copilot_editor_notification, user: user, notification_id: "copilot_seat_removed_#{organization.id}")
    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotSeatRemoved.new(copilot_user)
    assert notification.send_condition
    assert_equal "Your GitHub Copilot access has been disabled by the organization #{organization.display_login}.", notification.message
  end

  test "sends if we delete the seat" do
    user = create(:user)
    organization = create(:organization)
    organization.add_member(user)
    seat = create(:copilot_seat, organization: organization, assigned_user: user)
    seat.cancel!

    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotSeatRemoved.new(copilot_user)
    assert notification.send_condition
    assert_equal "Your GitHub Copilot access has been disabled by the organization #{organization.display_login}.", notification.message
  end

  test "it does not send if the organization has opted out of communications" do
    user = create(:user)
    organization = create(:organization)
    organization.add_member(user)

    enable_feature_flag(:copilot_communication_opt_out, organization)

    seat = create(:copilot_seat, organization: organization, assigned_user: user)
    seat.cancel!

    notification = Copilot::Notifications::CopilotSeatRemoved.new(user)
    refute notification.send_condition
  end
end if GitHub.copilot_enabled?
