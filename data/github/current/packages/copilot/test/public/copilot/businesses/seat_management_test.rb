# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Businesses::SeatManagementTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @business = create(:business, :enterprise_managed_business, seats_plan_type: "basic")
    @business_admin = @business.admins.first
  end

  context "#assign" do
    test "creates an enterprise team assignment for each assignable" do
      ent_team1 = create(:enterprise_team, business: @business)
      ent_team2 = create(:enterprise_team, business: @business)

      assert_changes -> { EnterpriseTeamAssignment.count }, from: 0, to: 2 do
        Copilot::Business.new(@business).assign([ent_team1, ent_team2], @business_admin)
      end
    end
  end

  context "#unassign" do
    test "destroys the enterprise team assignment for each assignable" do
      ent_team1 = create(:enterprise_team, business: @business)
      ent_team2 = create(:enterprise_team, business: @business)
      EnterpriseTeamAssignment.create!(enterprise_team: ent_team1, assignment_type: "copilot")
      EnterpriseTeamAssignment.create!(enterprise_team: ent_team2, assignment_type: "copilot")

      Copilot::Business.new(@business).assign([ent_team1, ent_team2], @business_admin)

      assert_changes -> { EnterpriseTeamAssignment.count }, from: 2, to: 0 do
        Copilot::Business.new(@business).unassign([ent_team1, ent_team2], @business_admin)
      end
    end
  end

  context "#copilot_standalone_seat_count" do
    test "works even when an assignment has a nil assignable" do
      assignment1 = create(:copilot_seat_assignment, :enterprise_team, business: @business, team_name: "team1")
      ent_team1 = assignment1.assignable
      assignment2 = create(:copilot_seat_assignment, :enterprise_team, business: @business, team_name: "team2")
      ent_team2 = assignment2.assignable

      EnterpriseTeamAssignment.create!(enterprise_team: ent_team1, assignment_type: "copilot")
      EnterpriseTeamAssignment.create!(enterprise_team: ent_team2, assignment_type: "copilot")

      Copilot::Business.new(@business).assign([ent_team1, ent_team2], @business_admin)

      ent_team2.destroy!

      assert_equal Copilot::Businesses::SeatManagement.copilot_standalone_seat_count(@business), 2
    end
  end
end if GitHub.copilot_enabled? && TestEnv.test_with_all_emus?
