# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Notifications::CopilotEnterpriseSeatAddedTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  setup do
    GitHub.flipper[:create_basic_enterprise].enable
    GitHub.flipper[:unaffiliated_user_accounts].enable
  end

  test "regular cfi users shouldn't hit this" do
    free_user = create(:copilot_free_user)
    user = free_user.user
    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotEnterpriseSeatAdded.new(copilot_user)
    refute notification.send_condition
  end

  test "regular seat users shouldn't hit this" do
    seat = create(:copilot_seat)
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)
    notification = Copilot::Notifications::CopilotEnterpriseSeatAdded.new(copilot_user)
    refute notification.send_condition
  end

  test "An enterprise team user should hit this" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    enterprise = seat_assignment.owner

    seat = seat_assignment.seats.first
    user = seat.assigned_user
    copilot_user = Copilot::User.new(user)

    notification = Copilot::Notifications::CopilotEnterpriseSeatAdded.new(copilot_user)

    assert notification.send_condition
    assert_equal "The enterprise #{enterprise.slug} has granted you access to GitHub Copilot.", notification.message
  end

  test "doesnt send if already sent" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    enterprise = seat_assignment.owner

    seat = seat_assignment.seats.first
    user = seat.assigned_user
    create(:copilot_editor_notification, user: user, notification_id: "copilot_enterprise_seat_added_#{enterprise.id}")
    copilot_user = Copilot::User.new(user)

    notification = Copilot::Notifications::CopilotEnterpriseSeatAdded.new(copilot_user)
    refute notification.send_condition
  end

  test "reports correct enterprise when a user belongs to multiple enterprises" do
    enterprise_a = create(:business, :default_managed, seats_plan_type: :basic)
    user = enterprise_a.members.first
    enterprise_b = create(:business, :default_managed, seats_plan_type: :basic)

    enterprise_team_a = create(:enterprise_team, business: enterprise_a)
    enterprise_team_b = create(:enterprise_team, business: enterprise_b)

    enterprise_team_a.enterprise_team_memberships.create!(user_id: user.id)
    enterprise_team_b.enterprise_team_memberships.create!(user_id: user.id)

    enterprise_b.add_owner(user, actor: user)

    seat_assignment_b = Copilot::SeatAssignment.create!(
      id: 1,
      owner_id: enterprise_b.id,
      owner_type: "Business",
      assignable_type: "EnterpriseTeam",
      assignable_id: enterprise_team_b.id,
      assigning_user: user
    )
    seat_assignment_b.convert_to_seats
    seat_assignment = Copilot::SeatAssignment.create!(
      id: 2,
      owner_id: enterprise_a.id,
      owner_type: "Business",
      assignable_type: "EnterpriseTeam",
      assignable_id: enterprise_team_a.id,
      assigning_user: user
    )
    seat_assignment.convert_to_seats

    notification = Copilot::Notifications::CopilotEnterpriseSeatAdded.new(Copilot::User.new(user))

    assert notification.send_condition
    Failbot.stubs(:report).never
    assert_match notification.message, "The enterprise #{enterprise_a.slug} has granted you access to GitHub Copilot."
  end
end if GitHub.copilot_enabled?
