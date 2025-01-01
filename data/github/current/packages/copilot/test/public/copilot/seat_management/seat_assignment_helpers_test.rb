# typed: true
# frozen_string_literal: true

require "test_helper"
class Copilot::SeatManagement::SeatAssignmentHelpersTest < GitHub::TestCase
  include CopilotTestHelper

  fixtures do
    @org = create(:organization)
    @user_in_org = create(:user)

    @team1 = create(:team, organization: @org)
    @team2 = create(:team, organization: @org)
    @team3 = create(:team, organization: @org)

    @team1.add_member(@user_in_org)
    @team1.add_member(create(:user)) # so that assignment for empty team is not destroyed
    @team2.add_member(@user_in_org)

    @team1_assignment = create(:copilot_seat_assignment, owner: @org, assignable: @team1, assigning_user: @org.admins.first)
    @team2_assignment = create(:copilot_seat_assignment, owner: @org, assignable: @team2, assigning_user: @org.admins.first)
    @team3_assignment = create(:copilot_seat_assignment, owner: @org, assignable: @team3, assigning_user: @org.admins.first)

    @user_in_org_seat = create(:copilot_seat, assigned_user: @user_in_org, seat_assignment: @team1_assignment)

    @biz = create(:business, :default_managed, seats_plan_type: :basic)

    @enterprise_team1 = create(:enterprise_team, name: "ent-team-1", business: @biz)
    @enterprise_team2 = create(:enterprise_team, name: "ent-team-2", business: @biz)

    @user_in_biz = create(:user)
    @biz.add_user_accounts([@user_in_biz.id], business_roles_bitfield: 0)

    [@enterprise_team1, @enterprise_team2].each do |ent_team|
      ent_team.enterprise_team_memberships.create!(user_id: @user_in_biz.id)
    end

    @enterprise_team1_assignment = create(:copilot_seat_assignment,
      :enterprise_team,
      supplied_business: @biz,
      assignable: @enterprise_team1,
    )
    @enterprise_team2_assignment = create(:copilot_seat_assignment,
      :enterprise_team,
      supplied_business: @biz,
      assignable: @enterprise_team2,
    )

    @user_in_biz_seat = create(:copilot_seat, assigned_user: @user_in_biz, seat_assignment: @enterprise_team1_assignment)
  end

  setup do
    enable_feature_flag(:copilot_revokable_access)
  end

  context "#other_team_or_enterprise_team_assignments_for_owner" do
    test "gets the other team assignments for the organization" do
      result = Copilot::SeatManagement::SeatAssignmentHelpers.other_team_or_enterprise_team_assignments_for_owner(@team1.id, @org)

      assert_includes result, @team2_assignment
      assert_includes result, @team3_assignment
      refute_includes result, @team1_assignment
    end

    test "gets the other enterprise team assignments for the enterprise" do
      result = Copilot::SeatManagement::SeatAssignmentHelpers.other_team_or_enterprise_team_assignments_for_owner(@enterprise_team1.id, @biz)

      assert_includes result, @enterprise_team2_assignment
      refute_includes result, @enterprise_team1_assignment
    end unless TestEnv.test_with_all_emus?

    test "gets the other enterprise team assignments for the enterprise (EMU mode)" do
      enterprise_team1_assignment = create(:copilot_seat_assignment, :enterprise_team)
      enterprise_team1 = enterprise_team1_assignment.assignable
      biz = enterprise_team1.business

      enterprise_team2_assignment = create(:copilot_seat_assignment, :enterprise_team, supplied_business: biz)

      result = Copilot::SeatManagement::SeatAssignmentHelpers.other_team_or_enterprise_team_assignments_for_owner(enterprise_team1.id, biz)

      assert_includes result, enterprise_team2_assignment
      refute_includes result, enterprise_team1_assignment
    end if TestEnv.test_with_all_emus?
  end

  context "other_team_or_enterprise_team_assignment_for_user" do
    test "raises error if assignment being checked is not a team/enterprise team assignment" do
      assignment = create(:copilot_seat_assignment, assignable: @org, owner: @org, assigning_user: @org.admins.first)

      assert_raises Copilot::Errors::SeatAssignmentError do
        Copilot::SeatManagement::SeatAssignmentHelpers.other_team_or_enterprise_team_assignment_for_user(@user_in_org, assignment)
      end
    end

    test "returns the other team assignment including the user" do
      result = Copilot::SeatManagement::SeatAssignmentHelpers.other_team_or_enterprise_team_assignment_for_user(@user_in_org, @team1_assignment)

      assert_equal @team2_assignment, result
    end

    test "returns the other enterprise team assignment including the user" do
      result = Copilot::SeatManagement::SeatAssignmentHelpers.other_team_or_enterprise_team_assignment_for_user(@user_in_biz, @enterprise_team1_assignment)

      assert_equal @enterprise_team2_assignment, result
    end unless TestEnv.test_with_all_emus?
  end

  context "#create_disassociated_seat_assignment" do
    context "for an org" do
      test "creates a disassociated user seat for a user without any existing user seat in an org" do
        logs = capture_logs do
          user_assignment = Copilot::SeatManagement::SeatAssignmentHelpers.create_disassociated_seat_assignment(@user_in_org.id, @user_in_org_seat, @team1_assignment, :test, @org.admins.first)
          assert_equal user_assignment.assignable_type, "User"
          assert_equal user_assignment.assignable_id, @user_in_org.id
        end

        assert_includes logs, "Created User SeatAssignment to disassociate from Team"
        refute_includes logs, "User already has User SeatAssignment, not creating one to disassociate."
      end

      test "doesn't create a new user assignment if one already exists" do
        user_seat_assignment = create(:copilot_seat_assignment, assignable: @user_in_org, assigning_user: @org.admins.first, owner: @org)

        assert_equal @user_in_org_seat.seat_assignment, @team1_assignment

        logs = capture_logs do
          user_assignment = Copilot::SeatManagement::SeatAssignmentHelpers.create_disassociated_seat_assignment(@user_in_org.id, @user_in_org_seat, @team1_assignment, :test, @org.admins.first)
          assert_equal user_assignment, user_seat_assignment
        end

        refute_includes logs, "Created User SeatAssignment to disassociate from Team"
        assert_includes logs, "User already has User SeatAssignment, not creating one to disassociate."
      end
    end

    context "for an enterprise" do
      test "with :copilot_revokable_access disabled raises a validation error" do
        disable_feature_flag(:copilot_revokable_access)

        assert_raises ActiveRecord::RecordInvalid do
          Copilot::SeatManagement::SeatAssignmentHelpers.create_disassociated_seat_assignment(@user_in_biz.id, @user_in_biz_seat, @enterprise_team1_assignment, :test, @biz.owners.first)
        end
      end

      test "with :copilot_revokable_access enabled creates a disassociated user seat for a user without any existing user seat in an enterprise" do
        logs = capture_logs do
          user_assignment = Copilot::SeatManagement::SeatAssignmentHelpers.create_disassociated_seat_assignment(@user_in_biz.id, @user_in_biz_seat, @enterprise_team1_assignment, :test, @biz.owners.first)
          assert_equal user_assignment.assignable_type, "User"
          assert_equal user_assignment.assignable_id, @user_in_biz.id
        end

        assert_includes logs, "Created User SeatAssignment to disassociate from EnterpriseTeam"
        refute_includes logs, "User already has User SeatAssignment, not creating one to disassociate."
      end

      test "doesn't create a new user assignment if one already exists" do
        user_seat_assignment = create(:copilot_seat_assignment, assignable: @user_in_biz, assigning_user: @biz.owners.first, owner: @biz)

        @user_in_biz_seat.update!(seat_assignment: user_seat_assignment)
        refute_equal @user_in_biz_seat.seat_assignment, @enterprise_team1_assignment

        logs = capture_logs do
          user_assignment = Copilot::SeatManagement::SeatAssignmentHelpers.create_disassociated_seat_assignment(@user_in_biz.id, @user_in_biz_seat, @enterprise_team1_assignment, :test, @biz.owners.first)
          assert_equal user_assignment, user_seat_assignment
        end

        refute_includes logs, "Created User SeatAssignment to disassociate from EnterpriseTeam"
        assert_includes logs, "User already has User SeatAssignment, not creating one to disassociate."
      end
    end unless TestEnv.test_with_all_emus?
  end
end unless GitHub.enterprise?
