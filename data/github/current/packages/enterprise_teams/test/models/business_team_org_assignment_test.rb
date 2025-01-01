# typed: true
# frozen_string_literal: true

require "test_helper"
class BusinessTeamOrgAssignmentTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @org0 = create(:organization, business: @business)
    @business_team = BusinessTeam.create!(name: "business-team", business: @business, organization_selection_type: :selected)
    @business_team_org0_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: @org0)

    GitHub.flipper["business_teams"].enable(@business)
    GitHub.flipper["enterprise_teams_enabled_for_organizations"].disable(@business)
  end

  context "relations" do
    test "belongs_to :team" do
      assert_equal @business_team, @business_team_org0_assignment.business_team
    end

    test "belongs_to :organization" do
      assert_equal @org0, @business_team_org0_assignment.organization
    end
  end
end
