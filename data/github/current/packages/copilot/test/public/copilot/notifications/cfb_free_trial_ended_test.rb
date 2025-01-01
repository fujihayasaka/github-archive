# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Notifications::CfbFreeTrialEndedTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @user = create(:user)
    @copilot_org = create(:copilot_for_business_enabled_organization, admin: @user)
    create(:copilot_seat, organization: @copilot_org, assigned_user: @user)
  end

  test "does not send a notification if no notification exists" do
    copilot_user = Copilot::User.new(@user)
    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    refute notification.send_condition
  end

  test "sends if the free trial has expired" do
    copilot_user = Copilot::User.new(@user)
    create(:copilot_business_trial, :organization, :expired, trialable: @copilot_org)
    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    assert notification.send_condition
    assert_equal "Your GitHub Copilot Business trial for the organization #{@copilot_org.display_login} has ended and was not renewed by your administrators. Contact them for more information.", notification.message
  end

  test "doesn't send if free trial hasn't ended yet" do
    copilot_user = Copilot::User.new(@user)
    create(:copilot_business_trial, :organization, :active, trialable: @copilot_org)

    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    refute notification.send_condition
  end

  test "doesn't send if free trial has been upgraded to paid" do
    copilot_user = Copilot::User.new(@user)
    create(:copilot_business_trial, :organization, trialable: @copilot_org, started_at: 30.days.ago, state: :upgraded, ends_at: 1.day.ago)
    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)

    refute notification.send_condition
  end

  test "doesn't send if org has no free trial" do
    seat = create(:copilot_seat)
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)

    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    refute notification.send_condition
  end

  test "A user assigned to two organizations that each have an ended trial should get two notifications" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)

    org1 = create(:copilot_for_business_enabled_organization, admin: user)
    org2 = create(:copilot_for_business_enabled_organization, admin: user)

    create(:copilot_seat, organization: org1, assigned_user: user)
    create(:copilot_seat, organization: org2, assigned_user: user)

    create(:copilot_business_trial, :organization, :expired, trialable: org1)
    create(:copilot_business_trial, :organization, :expired, trialable: org2)

    user.reload

    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    assert(notification.send_condition, "send_notification should be true as we haven't sent it yet")
    refute(notification.existing?, "existing? should be false as we haven't sent it yet")

    assert_includes notification.notification_id,
      org1.id.to_s,
      "notification_id should include the org's id"

    assert_includes notification.message,
      org1.display_login,
      "notification message should include the org's name"

    notification.store

    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    assert(notification.send_condition, "send_notification should be true because its a new org")
    refute(notification.existing?, "existing? should be false as this org hasnt been sent yet")
    assert(notification.notification_id.include?(org2.id.to_s), "notification_id should include the org's id")
    assert(notification.message.include?(org2.display_login), "notification message should include the org's name")
    notification.store

    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    refute(notification.send_condition, "send_notification should be false because there are no more notifications to send")
  end

  test "An enterprise team user shouldn't hit this" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats

    seat = seat_assignment.seats.first
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)

    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    refute notification.send_condition
  end

  test "it does not send if the organization has opted out of communications" do
    GitHub.flipper[:copilot_communication_opt_out].enable(@copilot_org)
    copilot_user = Copilot::User.new(@user)
    create(:copilot_business_trial, :organization, :expired, trialable: @copilot_org)
    notification = Copilot::Notifications::CfbFreeTrialEnded.new(copilot_user)
    refute notification.send_condition
  end
end if GitHub.copilot_enabled?
