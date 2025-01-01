# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessTeamTest < GitHub::TestCase
  fixtures do
    @business = create(:business)
    @org0 = create(:organization, business: @business)
    @org1 = create(:organization, business: @business)
    @org2 = create(:organization, business: @business)
    @business_team = BusinessTeam.create!(name: "business-team", business: @business, organization_selection_type: :selected)
    @business_team_org0_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: @org0)
    @business_team_org1_assignment = BusinessTeamOrgAssignment.create!(business_team: @business_team, organization: @org1)
    @global_business_team = BusinessTeam.create!(name: "global-business-team", business: @business, organization_selection_type: :all)

    GitHub.flipper["business_teams"].enable(@business)
    GitHub.flipper["enterprise_teams_enabled_for_organizations"].disable(@business)
  end

  context "default_scope" do
    test "is undoing orgid is not null" do
      expected_team = BusinessTeam.create!(name: "some-team", slug: "some-team", business: @business)
      actual_team = BusinessTeam.find_by(business: @business, slug: "some-team")
      refute_nil actual_team
      assert_equal expected_team, actual_team
      assert_nil T.must(actual_team).organization_id
    end
  end

  context "validations" do
    test "validates presence of business" do
      assert_raises(ActiveRecord::RecordInvalid) do
        BusinessTeam.create!(name: "some-team", business: nil)
      end

      assert_predicate BusinessTeam.create(name: "some-team", business: @business), :valid?
    end

    test "validates correct organization_selection_type" do
      assert_raises ArgumentError do
        @business_team.organization_selection_type = :foo
      end
    end

    test "validates uniqueness of name scoped to business_id" do
      business_team = BusinessTeam.create!(name: "Unique Team", business: @business)
      duplicate_team = BusinessTeam.new(name: "UNIQUE TEAM", business: @business)

      refute duplicate_team.valid?
      assert_match(/has already been taken/, duplicate_team.errors[:name].first)
    end

    test "validates absence of organization_id" do
      assert_raises(ActiveRecord::RecordInvalid) do
        BusinessTeam.create!(name: "some-team", business: @business, organization_id: @org0.id)
      end

      assert_raises(ActiveRecord::RecordInvalid) do
        @business_team.update!(organization_id: @org0.id)
      end
    end
  end

  context "relations" do
    test "#belongs_to :business" do
      assert_equal @business, @business_team.business
    end

    test "#has_many :business_team_org_assignments" do
      assert_same_elements [@business_team_org0_assignment, @business_team_org1_assignment], @business_team.business_team_org_assignments
    end

    test "#has_many :selected_organizations" do
      assert_same_elements [@org0, @org1], @business_team.selected_organizations
      assert_empty @global_business_team.selected_organizations
    end
  end

  test "business_team?" do
    assert @business_team.business_team?
  end

  context "enabled_for_enterprise?" do
    test "returns false if business is nil" do
      refute BusinessTeam.enabled_for_enterprise?(business: nil)
    end

    test "returns false if enterprise_teams_enabled_for_organizations is enabled" do
      EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
      refute BusinessTeam.enabled_for_enterprise?(business: @business)
    end

    test "returns false if business_teams_enabled_for_enterprise is not enabled" do
      GitHub.flipper["business_teams"].disable(@business)
      refute BusinessTeam.enabled_for_enterprise?(business: @business)
    end

    test "returns true if business_teams_enabled_for_enterprise is enabled" do
      assert BusinessTeam.enabled_for_enterprise?(business: @business)
    end
  end

  context "organization_ids" do
    test "returns all organization ids if organization_selection_type is all_orgs" do
      assert_same_elements @business.organization_ids, @global_business_team.organization_ids
    end

    test "returns selected organization ids if organization_selection_type is selected_orgs" do
      assert_same_elements [@org0.id, @org1.id], @business_team.organization_ids
    end
  end

  context "add_to_organizations" do
    test "does nothing if organization_selection_type is all_orgs" do
      @global_business_team.add_to_organizations(org_ids: [@org2.id])
      assert_empty @global_business_team.selected_organizations
    end

    test "adds the team to the selected organizations" do
      @business_team.add_to_organizations(org_ids: [@org2.id])
      assert_same_elements @business.organizations, @business_team.reload.selected_organizations
    end
  end

  context "remove_from_organizations" do
    test "removes the team from the selected organization" do
      @business_team.remove_from_organizations(org_ids: [@org0.id])
      assert_equal [@org1], @business_team.selected_organizations
    end

    test "removes the team from the selected organizations" do
      @business_team.remove_from_organizations(org_ids: [@org0.id, @org1.id])
      assert_empty @business_team.selected_organizations
    end
  end

  context "slug generation" do
    test "generates a slug from the business team name" do
      business_team = BusinessTeam.create!(name: "Fun name", business: @business)
      assert_equal "fun-name", business_team.slug
    end

    test "generates a unique slug when same slug exists" do
      business_team1 = BusinessTeam.create!(name: "Fun name yay", business: @business)
      business_team2 = BusinessTeam.create!(name: "Fun-name yay", business: @business)
      business_team3 = BusinessTeam.create!(name: "Fun name-yay", business: @business)

      assert_equal "fun-name-yay", business_team1.slug
      assert_equal "fun-name-yay-1", business_team2.slug
      assert_equal "fun-name-yay-2", business_team3.slug
    end

    test "different businesses can have the same slug" do
      @business2 = create :business
      business_team = BusinessTeam.create!(name: "Same name", business: @business,)
      team_from_different_org = BusinessTeam.create!(name: "Same name", business: @business2)
      assert_equal "same-name", business_team.slug
      assert_equal "same-name", team_from_different_org.slug
    end unless GitHub.single_business_environment?

    test "does not do anything if the name has not changed" do
      business_team = BusinessTeam.create!(name: "Not changed", business: @business)
      business_team.reload
      business_team.expects(:generate_unique_slug).never
      business_team.save!
    end

    test "regenerates the slug when the name changes" do
      business_team = BusinessTeam.create!(name: "Not changed", business: @business)
      business_team.name = "Name has been changed"
      business_team.save!
      assert_equal "name-has-been-changed", business_team.slug
    end

    test "combined_slug" do
      assert_equal "/business-team", @business_team.combined_slug
    end
  end
end
