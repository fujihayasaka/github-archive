# typed: true
# frozen_string_literal: true

require "test_helper"

class CopilotUsersMailableTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags
  test "opted in for copilot communication by default" do
    refute Copilot::User.new(create(:user)).copilot_communication_opt_out?
  end

  test "opted in for copilot communication with cfi access" do
    Copilot::User.any_instance.stubs(:has_cfi_access?).returns(true)
    refute Copilot::User.new(create(:user)).copilot_communication_opt_out?
  end

  test "opted out for copilot communication with cfi access and feature flag enabled" do
    Copilot::User.any_instance.stubs(:has_cfi_access?).returns(true)
    enable_feature_flag(:copilot_communication_opt_out)
    assert Copilot::User.new(create(:user)).copilot_communication_opt_out?
  end

  test "user with business owned org is opted in for copilot communication by default" do
    org = create(:copilot_for_business_enabled_organization)
    refute Copilot::User.new(org.admins.first).copilot_communication_opt_out?
  end

  test "user with business owned org is opted out for copilot communication when the flag is enabled" do
    org = create(:copilot_for_business_enabled_organization)
    create(:copilot_seat, organization: org, assigned_user: org.admins.first)
    enable_feature_flag(:copilot_communication_opt_out)
    assert Copilot::User.new(org.admins.first).copilot_communication_opt_out?
  end

  test "user with standalone org is opted in for copilot communication by default" do
    org = create(:organization)
    create(:copilot_seat, organization: org, assigned_user: org.admins.first)
    refute Copilot::User.new(org.admins.first).copilot_communication_opt_out?
  end

  test "user with standalone org is opted out for copilot communication when the flag is enabled" do
    org = create(:organization)
    create(:copilot_seat, organization: org, assigned_user: org.admins.first)
    enable_feature_flag(:copilot_communication_opt_out)
    assert Copilot::User.new(org.admins.first).copilot_communication_opt_out?
  end

  test "user with standalone business is opted in for copilot communication by default" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    copilot_user = Copilot::User.new(seat_assignment.seats.first.assigned_user)
    refute copilot_user.copilot_communication_opt_out?
  end

  test "user with standalone business is opted out for copilot communication when the flag is enabled" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    copilot_user = Copilot::User.new(seat_assignment.seats.first.assigned_user)
    enable_feature_flag(:copilot_communication_opt_out)
    assert copilot_user.copilot_communication_opt_out?
  end

  test "guest collaborator with standalone business is opted in for copilot communication by default" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    copilot_user = Copilot::User.new(seat_assignment.seats.first.assigned_user)
    copilot_user.user_object.stubs(:guest_collaborator?).returns(true)
    refute copilot_user.copilot_communication_opt_out?
  end

  test "guest collaborator with standalone business is opted out for copilot communication when the flag is enabled" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    seat_assignment.convert_to_seats
    copilot_user = Copilot::User.new(seat_assignment.seats.first.assigned_user)
    copilot_user.user_object.stubs(:guest_collaborator?).returns(true)
    enable_feature_flag(:copilot_communication_opt_out)
    assert copilot_user.copilot_communication_opt_out?
  end

  test "non-emu standalone business is opted in for copilot communication by default and opted out when feature flag is enabled" do
    biz = create(:business)
    biz.update(seats_plan_type: :basic)

    team = create(:enterprise_team, business: biz)
    user = create(:user)
    biz.add_user_accounts([user.id], business_roles_bitfield: 0)
    team.enterprise_team_memberships.create!(user_id: user.id)

    assignment = Copilot::SeatAssignment.new(
      owner_id: team.business_id,
      owner_type: "Business",
      assignable_type: "EnterpriseTeam",
      assignable_id: team.id,
      assigning_user: team.business.owners.first,
    )
    assignment.save!
    assignment.convert_to_seats

    copilot_user = Copilot::User.new(user)

    refute copilot_user.copilot_communication_opt_out?
    enable_feature_flag(:copilot_communication_opt_out)
    assert Copilot::User.new(user).copilot_communication_opt_out?
  end
end if GitHub.copilot_enabled?
