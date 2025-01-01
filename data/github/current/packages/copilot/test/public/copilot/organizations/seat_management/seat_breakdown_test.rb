# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::Organizations::SeatManagement::SeatBreakdownTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "1 seat assigned (1 billed)" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    create(:copilot_seat, organization: organization)
    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 1, seat_breakdown.seats_assigned
    assert_equal 1, seat_breakdown.seats_billed
    assert_equal 0, seat_breakdown.seats_pending
    assert_equal "1 seat assigned (1 billed)", seat_breakdown.to_s
  end

  test "0 seats assigned (1 billed)" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    seat = create(:copilot_seat, organization: organization)
    seat.seat_assignment.update_column(:pending_cancellation_date, Time.current)

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)

    assert_equal 0, seat_breakdown.seats_assigned
    assert_equal 1, seat_breakdown.seats_billed
    assert_equal 0, seat_breakdown.seats_pending
    assert_equal "0 seats assigned (1 billed)", seat_breakdown.to_s
  end

  test "0 seats assigned (1 pending)" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    invitation = organization.invite(user, inviter: organization.admin, role: :direct_member)

    create(:copilot_seat_assignment, organization: organization, assignable: invitation, assigning_user: organization.admin)
    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 0, seat_breakdown.seats_assigned
    assert_equal 0, seat_breakdown.seats_billed
    assert_equal 1, seat_breakdown.seats_pending
    assert_equal "0 seats assigned (1 pending)", seat_breakdown.to_s
  end

  test "0 seats assigned (1 billed / 1 pending)" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    # create assignment pending cancellation
    assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin, pending_cancellation_date: Time.current + 10.days)
    create(:copilot_seat, organization: organization, seat_assignment: assignment, assigned_user: user)

    # create invitation
    invitation = organization.invite(create(:user), inviter: organization.admin, role: :direct_member)
    create(:copilot_seat_assignment, organization: organization, assignable: invitation, assigning_user: organization.admin)

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 0, seat_breakdown.seats_assigned
    assert_equal 1, seat_breakdown.seats_billed
    assert_equal 1, seat_breakdown.seats_pending
    assert_equal "0 seats assigned (1 billed / 1 pending)", seat_breakdown.to_s
  end

  test "1 seat assigned (1 billed / 1 pending)" do
    organization = create(:copilot_for_business_enabled_organization)
    user = create(:user)
    organization.add_member(user)

    # create assignment
    assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
    create(:copilot_seat, organization: organization, seat_assignment: assignment, assigned_user: user)

    # create invitation
    invitation = organization.invite(create(:user), inviter: organization.admin, role: :direct_member)
    create(:copilot_seat_assignment, organization: organization, assignable: invitation, assigning_user: organization.admin)

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 1, seat_breakdown.seats_assigned
    assert_equal 1, seat_breakdown.seats_billed
    assert_equal 1, seat_breakdown.seats_pending
    assert_equal "1 seat assigned (1 billed / 1 pending)", seat_breakdown.to_s
  end

  test "seat breakdown is correct for team assignments" do
    organization = create(:copilot_for_business_enabled_organization)
    parent_team = create(:team, organization: organization, privacy: :closed)
    child_team = create(:team, organization: organization, privacy: :closed, parent_team_id: parent_team.id)

    # 5 parent team members
    5.times do
      user = create(:user)
      organization.add_member(user)
      parent_team.add_member(user)
    end

    # 3 child team members
    # TODO: we do NOT handle seat assignments or seats for child teams, see TeamConverterCommand
    3.times do
      user = create(:user)
      organization.add_member(user)
      child_team.add_member(user)
    end

    team_assignment = create(:copilot_seat_assignment, organization: organization, assignable: parent_team, assigning_user: organization.admin)
    team_assignment.convert_to_seats

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 5, seat_breakdown.seats_assigned
    assert_equal 5, seat_breakdown.seats_billed
    assert_equal 0, seat_breakdown.seats_pending
    assert_equal "5 seats assigned (5 billed)", seat_breakdown.to_s
  end

  test "seat breakdown is correct for team assignments when there's an existing user seat" do
    organization = create(:copilot_for_business_enabled_organization)
    parent_team = create(:team, organization: organization, privacy: :closed)
    child_team = create(:team, organization: organization, privacy: :closed, parent_team_id: parent_team.id)

    # 5 parent team members
    5.times do
      user = create(:user)
      organization.add_member(user)
      parent_team.add_member(user)
    end

    # 3 child team members
    # TODO: we do NOT handle seat assignments or seats for child teams, see TeamConverterCommand
    3.times do
      user = create(:user)
      organization.add_member(user)
      child_team.add_member(user)
    end

    user = create(:user)
    organization.add_member(user)
    user_assignment = create(:copilot_seat_assignment, organization: organization, assignable: user, assigning_user: organization.admin)
    user_assignment.convert_to_seats

    parent_team.add_member(user)
    team_assignment = create(:copilot_seat_assignment, organization: organization, assignable: parent_team, assigning_user: organization.admin)
    team_assignment.convert_to_seats

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 6, seat_breakdown.seats_assigned
    # since we originally had an organization seat, 9 seats are being billed this cycle
    assert_equal 6, seat_breakdown.seats_billed
    assert_equal 0, seat_breakdown.seats_pending
    assert_equal "6 seats assigned (6 billed)", seat_breakdown.to_s
  end

  test "seat breakdown is correct for team assignments after organization seat assignment already existed" do
    organization = create(:copilot_for_business_enabled_organization)
    parent_team = create(:team, organization: organization, privacy: :closed)
    child_team = create(:team, organization: organization, privacy: :closed, parent_team_id: parent_team.id)

    # 5 parent team members
    5.times do
      user = create(:user)
      organization.add_member(user)
      parent_team.add_member(user)
    end

    # 3 child team members
    # TODO: we do NOT handle seat assignments or seats for child teams, see TeamConverterCommand
    3.times do
      user = create(:user)
      organization.add_member(user)
      child_team.add_member(user)
    end

    # let's make sure this works even when there's an existing organization seat
    org_assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization, assigning_user: organization.admin)
    org_assignment.convert_to_seats
    org_assignment.unassign!(organization.admin)

    team_assignment = create(:copilot_seat_assignment, organization: organization, assignable: parent_team, assigning_user: organization.admin)
    team_assignment.convert_to_seats

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 5, seat_breakdown.seats_assigned
    # since we originally had an organization seat, 9 seats are being billed this cycle
    assert_equal 9, seat_breakdown.seats_billed
    assert_equal 0, seat_breakdown.seats_pending
    assert_equal "5 seats assigned (9 billed)", seat_breakdown.to_s
  end


  test "seat breakdown is correct for organization assignment" do
    organization = create(:copilot_for_business_enabled_organization)
    5.times do
      user = create(:user)
      organization.add_member(user)
    end

    assignment = create(:copilot_seat_assignment, organization: organization, assignable: organization, assigning_user: organization.admin)
    assignment.convert_to_seats

    seat_breakdown = Copilot::Organizations::SeatManagement::SeatBreakdown.new(organization)
    assert_equal 6, seat_breakdown.seats_assigned
    assert_equal 6, seat_breakdown.seats_billed
    assert_equal 0, seat_breakdown.seats_pending
    assert_equal "6 seats assigned (6 billed)", seat_breakdown.to_s
  end
end if GitHub.copilot_enabled?
