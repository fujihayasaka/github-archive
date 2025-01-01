# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTeamsDependencyTest < GitHub::TestCase
  setup do
    @admin = create :user
    @business = create :business, owners: [@admin]
    @org = create :business_plus_organization, business: @business, admins: [@admin]
    @business_team = create :business_team, business: @business, orgs: [@org]
    @global_business_team = BusinessTeam.create!(name: "global-business-team", business: @business, organization_selection_type: :all)
    @member = create :user
    @org.add_member(@member)

    enable_feature_flag(:enterprise_teams_org_assignment, @business)
    enable_feature_flag(:enterprise_teams_crud, @business)
  end

  context "#business_team_prevents_removal_from_org?" do
    test "returns true for user in a BT that has been granted access to all orgs" do
      @global_business_team.add_member(@member, caller_type: :business_team)
      assert @org.business_team_prevents_removal_from_org?(@member)
    end

    test "returns true for a user in a BT that has been granted access to one org" do
      @business_team.add_member(@member, caller_type: :business_team)
      assert @org.business_team_prevents_removal_from_org?(@member)
    end

    test "returns false for a user not granted membership through a BT" do
      refute @org.business_team_prevents_removal_from_org?(@member)
    end
  end

  context "#prevent_removal_of_business_team_members_from_org" do
    test "removes a user from an array if a user in a BT that has been granted access to all orgs" do
      @global_business_team.add_member(@member, caller_type: :business_team)
      assert_empty @org.prevent_removal_of_business_team_members_from_org([@member])
    end

    test "removes a user from an array if a user in a BT that has been granted access to one org" do
      @business_team.add_member(@member, caller_type: :business_team)
      assert_empty @org.prevent_removal_of_business_team_members_from_org([@member])
    end

    test "returns a user in an array if a user not granted membership through a BT" do
      assert_same_elements [@member], @org.prevent_removal_of_business_team_members_from_org([@member])
    end
  end
end
