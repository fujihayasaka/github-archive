# typed: true
# frozen_string_literal: true

require "test_helper"
class BusinessTeamOrgAssignmentTest < GitHub::TestCase

  fixtures do
    @business = create(:business)
    @org0 = create(:organization, business: @business)
    @business_team = BusinessTeam.create!(name: "business-team", business: @business, organization_selection_type: :selected)
    @business_team_org0_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: @org0)

    enable_feature_flag(:enterprise_teams_crud, @business)
    enable_feature_flag(:enterprise_teams_org_assignment, @business)
    disable_feature_flag(:enterprise_teams_enabled_for_organizations, @business)
  end

  context "validations" do
    test "validates presence of business_team" do
      org = create(:organization, business: @business)
      assert_raises(ActiveRecord::RecordInvalid) do
        BusinessTeamOrgAssignment.create!(business_team: nil, organization: org)
      end

      assert_predicate BusinessTeamOrgAssignment.create(business_team: @business_team, organization: org), :valid?
    end

    test "validates presence of organization" do
      org = create(:organization, business: @business)
      assert_raises(ActiveRecord::RecordInvalid) do
        BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: nil)
      end

      assert_predicate BusinessTeamOrgAssignment.create(business_team: @business_team, organization: org), :valid?
    end

    test "validates business has not reached team assignment limit on creation" do
      org1 = create(:organization, business: @business)
      no_limit_assignment = BusinessTeamOrgAssignment.create(business_team: @business_team, organization: org1)
      assert_predicate no_limit_assignment, :valid?

      org2 = create(:organization, business: @business)
      BusinessTeam.any_instance.stubs(:organization_assignment_limit_reached?).returns(true)
      limit_assignment = BusinessTeamOrgAssignment.create(business_team: @business_team, organization: org2)
      refute_predicate limit_assignment, :valid?
      refute_nil limit_assignment.errors.of_kind?(:business_team, "organization assignment limit reached")
    end
  end

  context "relations" do
    test "belongs_to :team" do
      assert_equal @business_team, @business_team_org0_assignment.business_team
    end

    test "belongs_to :organization" do
      assert_equal @org0, @business_team_org0_assignment.organization
    end

    test "destroy organization assignment when organization is destroyed" do
      org1 = create(:organization, business: @business)
      business_team1 = create(:business_team, business: @business, name: "selected1", organization_selection_type: :selected)
      business_team1.add_to_organizations(org_ids: [org1])
      business_team2 = create(:business_team, business: @business, name: "selected2", organization_selection_type: :selected)
      business_team2.add_to_organizations(org_ids: [org1])

      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team2).count
      perform_enqueued_jobs only: [DestroyDependentRecordsJob] do
        org1.destroy!
      end
      assert_equal 0, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 0, BusinessTeamOrgAssignment.where(business_team: business_team2).count
    end

    test "do not destroy organization assignment when organization is soft deleted", skip_enterprise: true do
      org1 = create(:organization, business: @business)
      business_team1 = create(:business_team, business: @business, name: "selected1", organization_selection_type: :selected)
      business_team1.add_to_organizations(org_ids: [org1])
      business_team2 = create(:business_team, business: @business, name: "selected2", organization_selection_type: :selected)
      business_team2.add_to_organizations(org_ids: [org1])

      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team2).count
      assert_no_enqueued_jobs only: [ClearBusinessTeamOrgAssignmentsJob, DestroyDependentRecordsJob] do
        org1.soft_delete!
      end
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team2).count
    end

    test "destroy organization assignment when organization is removed from a business", skip_with_all_emus: true do
      org1 = create(:organization, business: @business)
      business_team1 = create(:business_team, business: @business, name: "selected1", organization_selection_type: :selected)
      business_team1.add_to_organizations(org_ids: [org1])
      business_team2 = create(:business_team, business: @business, name: "selected2", organization_selection_type: :selected)
      business_team2.add_to_organizations(org_ids: [org1])

      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team2).count
      perform_enqueued_jobs only: [ClearBusinessTeamOrgAssignmentsJob] do
        @business.remove_organization(org1)
      end
      assert_equal 0, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 0, BusinessTeamOrgAssignment.where(business_team: business_team2).count
    end

    test "do not destroy organization assignment when organization is removed from a business if FF disabled", skip_with_all_emus: true do
      disable_feature_flag(:enterprise_teams_org_assignment)
      disable_feature_flag(:erp_preview)
      disable_feature_flag(:erp_staffship)

      org1 = create(:organization, business: @business)
      business_team1 = create(:business_team, business: @business, name: "selected1", organization_selection_type: :selected)
      business_team1.add_to_organizations(org_ids: [org1])
      business_team2 = create(:business_team, business: @business, name: "selected2", organization_selection_type: :selected)
      business_team2.add_to_organizations(org_ids: [org1])

      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team2).count
      assert_no_enqueued_jobs only: [ClearBusinessTeamOrgAssignmentsJob] do
        @business.remove_organization(org1)
      end
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team1).count
      assert_equal 1, BusinessTeamOrgAssignment.where(business_team: business_team2).count
    end
  end
end
