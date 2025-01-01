# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Notifications::CopilotSeatAddedTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "sends a notification if not sent previously" do
    seat = create(:copilot_seat)
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotSeatAdded.new(copilot_user)
    assert notification.send_condition
    assert_equal "The organization #{seat.organization.name} has granted you access to GitHub Copilot.", notification.message
  end

  test "doesnt send if already sent" do
    seat = create(:copilot_seat)
    user = seat.assigned_user
    create(:copilot_editor_notification, user: user, notification_id: "copilot_seat_added_#{seat.id}")
    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotSeatAdded.new(copilot_user)
    refute notification.send_condition
  end

  test "sends for any in the collection" do
    user = create(:user)
    orga = create(:copilot_for_business_enabled_organization)
    orga.add_member(user)
    orgb = create(:copilot_for_business_enabled_organization)
    orgb.add_member(user)

    seat = create(:copilot_seat, organization: orga, assigned_user: user)
    other_seat = create(:copilot_seat, organization: orgb, assigned_user: user)

    create(:copilot_editor_notification, user: user, notification_id: "copilot_seat_added_#{seat.id}")
    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotSeatAdded.new(copilot_user)
    assert notification.send_condition

    assert_equal "The organization #{other_seat.organization.name} has granted you access to GitHub Copilot.", notification.message
  end

  test "An enterprise team user shouldn't hit this" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats

    seat = seat_assignment.seats.first
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)

    notification = Copilot::Notifications::CopilotSeatAdded.new(copilot_user)
    refute notification.send_condition
  end

  test "it does not send if the organization has opted out of communications" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)

    organization.add_member(user)

    GitHub.flipper[:copilot_communication_opt_out].enable(organization)
    create(:copilot_seat, organization: organization, assigned_user: user)

    notification = Copilot::Notifications::CopilotSeatAdded.new(user)
    refute notification.send_condition
  end
end if GitHub.copilot_enabled?
