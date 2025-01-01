# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Notifications::CfbFreeTrialWelcomeTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @seat = create(:copilot_seat)
    @user = @seat.assigned_user
    @org = @seat.organization
  end

  test "does not send notification if there is no trial" do
    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(create(:user))
    refute notification.send_condition
  end

  test "does not send a notification if there is a trial but it is not active" do
    # the trial ended, therefore no longer active
    create(:copilot_business_trial, :organization, trialable: @org, state: :expired)
    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(Copilot::User.new(@user))
    refute notification.send_condition
  end

  test "sends a notification if there is an active trial" do
    create(:copilot_business_trial, :organization, trialable: @org)
    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(Copilot::User.new(@user))
    assert notification.send_condition
  end

  test "only sends a notification for the first time" do
    create(:copilot_business_trial, :organization, trialable: @org)

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(Copilot::User.new(@user))
    assert notification.send_condition
    refute notification.existing?
    notification.store

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(Copilot::User.new(@user))
    refute(notification.send_condition, "send_notification should be false as it's existing")
  end

  test "sends a notification for the latest trial" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)
    org_1 = create(:copilot_for_business_enabled_organization, admin: user)
    org_2 = create(:copilot_for_business_enabled_organization, admin: user)

    # assign some seats to these orgs
    create(:copilot_seat, organization: org_1, assigned_user: user)
    create(:copilot_seat, organization: org_2, assigned_user: user)

    # 2 orgs, 1 user, each org has a seat for that user

    # now lets start some trials
    create(:copilot_business_trial, :organization, trialable: org_1, started_at: 1.day.ago)
    create(:copilot_business_trial, :organization, trialable: org_2, started_at: 2.days.ago)

    user.reload

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    assert notification.send_condition
    notification.store

    # its org because its the latest trial
    assert(notification.message.include?(org_1.display_login), "expected to see #{org_1.display_login} in the message as it was the latest created trial\nmessage: #{notification.message}")

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    assert notification.send_condition
    notification.store

    # we should see one more notification for org_2
    assert(notification.message.include?(org_2.display_login), "expected to see #{org_2.display_login} in the message as it was the latest created trial\nmessage: #{notification.message}")
  end

  test "only notifiy for copilot seats" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)

    create(:enterprise_linked_organization, admin: user)
    copilot_org = create(:copilot_for_business_enabled_organization, admin: user)

    create(:copilot_seat, organization: copilot_org, assigned_user: user)
    create(:copilot_business_trial, :organization, trialable: copilot_org)

    user.reload

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    assert notification.send_condition
    notification.store

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    refute notification.send_condition
  end

  test "orgs created later with a new trial should also send notification" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)

    org = create(:copilot_for_business_enabled_organization, admin: user)
    create(:copilot_seat, organization: org, assigned_user: user)
    create(:copilot_business_trial, :organization, trialable: org)

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    assert(notification.send_condition, "send_notification should be true as we haven't sent it yet")
    refute(notification.existing?, "existing? should be false as we haven't sent it yet")
    notification.store

    # another org, so should send notification again
    org = create(:copilot_for_business_enabled_organization, admin: user)
    user.reload
    create(:copilot_seat, organization: org, assigned_user: user)
    create(:copilot_business_trial, :organization, trialable: org)

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    assert(notification.send_condition, "send_notification should be true because its a new org")
    refute(notification.existing?, "existing? should be false as this org hasnt been sent yet")
  end

  test "An enterprise team user shouldn't hit this" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats

    seat = seat_assignment.seats.first
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    refute notification.send_condition
  end

  test "it does not send if the organization has opted out of communications" do
    user = create(:user)
    copilot_user = Copilot::User.new(user)

    create(:enterprise_linked_organization, admin: user)
    copilot_org = create(:copilot_for_business_enabled_organization, admin: user)

    enable_feature_flag(:copilot_communication_opt_out, copilot_org)

    create(:copilot_seat, organization: copilot_org, assigned_user: user)
    create(:copilot_business_trial, :organization, trialable: copilot_org)

    user.reload

    notification = Copilot::Notifications::CfbFreeTrialWelcome.new(copilot_user)
    refute notification.send_condition
  end
end if GitHub.copilot_enabled?
