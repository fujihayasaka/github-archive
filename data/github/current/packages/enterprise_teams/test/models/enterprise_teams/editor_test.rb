# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamEditorTest < GitHub::TestCase
  setup do
    @enterprise = create :business
    @business_admin = create :user
    @team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Old Team", sync_to_organizations: "disabled", idp_group_id: nil, is_security_manager: false)

    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
  end

  test "update a team" do
    updated_team = EnterpriseTeams::Editor.update_team(enterprise: @enterprise, team_slug: @team.slug, team_name: "New Team", sync_to_organizations: "disabled", idp_group_id: nil, is_security_manager: false)
    assert_equal "New Team", updated_team.name
    assert_equal "disabled", updated_team.sync_to_organizations
  end

  test "update a team with invalid parameters" do
    assert_raises(ActiveRecord::RecordInvalid) do
      EnterpriseTeams::Editor.update_team(enterprise: @enterprise, team_slug: @team.slug, team_name: "", sync_to_organizations: "invalid", idp_group_id: nil, is_security_manager: false)
    end
  end
end

class SCIMBasedEnterpriseTeamEditorTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @enterprise = create :global_business
      @provider = @enterprise.external_provider
    else
      user = create(:emu, :owner, login: "org-admin")
      @enterprise = user.enterprise_managed_business
    end

    @owner = @enterprise.owners.first
    @org = create :organization, business: @enterprise, admin: @owner
    @external_group = create :external_group, :with_members, business: @enterprise, number_of_members: 2
    @external_group_users = @external_group.external_identity_group_memberships.map(&:external_identity).map(&:user)
    @group_mappings = [{ group_id: @external_group.id.to_s }]

    @team = EnterpriseTeams::Factory.create_enterprise_team(enterprise: @enterprise, team_name: "Old Team", sync_to_organizations: "disabled", idp_group_id: nil, is_security_manager: false)
  end

  setup do
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    EnterpriseTeam.stubs(:enabled_for_organization_security_manager?).returns(true)
    if GitHub.single_business_environment?
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
    end
  end

  test "update a team with idp_group_id" do
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(false)
    assert_no_difference ["EnterpriseTeam.count"] do
      assert_difference ["EnterpriseTeamGroupMapping.count"], 1 do
        updated_team = EnterpriseTeams::Editor.update_team(enterprise: @enterprise, team_slug: @team.slug, team_name: "Test Team", sync_to_organizations: "disabled", idp_group_id: @external_group.id, is_security_manager: false)
        assert_equal "Test Team", updated_team.name
        assert_equal "disabled", updated_team.sync_to_organizations
        assert_equal @external_group.id, T.must(updated_team.enterprise_team_group_mappings.first).external_group_id
      end
    end
  end

  test "update a team with idp_group_id in GHES" do
    EnterpriseTeams::Helper.stubs(:idp_group_disabled?).returns(true)
    assert_no_difference ["EnterpriseTeam.count"] do
      assert_no_difference ["EnterpriseTeamGroupMapping.count"], 1 do
        assert_raises_with_message(ArgumentError, "External groups for enterprise teams are not supported on GHES.") do
          updated_team = EnterpriseTeams::Editor.update_team(enterprise: @enterprise, team_slug: @team.slug, team_name: "Test Team", sync_to_organizations: "disabled", idp_group_id: @external_group.id, is_security_manager: false)
          assert_equal "Test Team", @team.name
          assert_equal "disabled", @team.sync_to_organizations
          assert_nil @external_group.id
        end
      end
    end
  end
end

class BusinessTeamEditorTest < GitHub::TestCase
  setup do
    Business::OrganizationMembership.any_instance.stubs(:ensure_business_has_enough_seats).returns(true)
    @business = create(:business)
    @organization1 = create(:organization, business: @business)
    @organization2 = create(:organization, business: @business)
    @team = create(:business_team, business: @business, name: "Old Team", description: "Old Description", organization_selection_type: :selected)
    @team.add_to_organizations(org_ids: [@organization1.id, @organization2.id])
  end

  test "update a business team" do
    updated_team = EnterpriseTeams::Editor.update_business_team(
      business: @business,
      team_slug: @team.slug,
      team_name: "New Team",
      description: "New Description",
      organization_selection_type: :all
    )

    assert_equal "New Team", updated_team.name
    assert_equal "New Description", updated_team.description
    assert_equal :all, updated_team.organization_selection_type.to_sym
  end

  test "update a non-existent business team" do
    assert_raises(ActiveRecord::RecordNotFound) do
      EnterpriseTeams::Editor.update_business_team(
        business: @business,
        team_slug: "non-existent-slug",
        team_name: "New Team",
        description: "New Description",
        organization_selection_type: :all
      )
    end
  end

  test "update a business team with invalid parameters" do
    assert_raises(ActiveRecord::RecordInvalid) do
      EnterpriseTeams::Editor.update_business_team(
        business: @business,
        team_slug: @team.slug,
        team_name: "",
        description: "New Description",
        organization_selection_type: :all
      )
    end
  end

  test "update a business team when save fails" do
    BusinessTeam.any_instance.stubs(:save!).raises(ActiveRecord::RecordInvalid.new(BusinessTeam.new))

    assert_raises(ActiveRecord::RecordInvalid) do
      EnterpriseTeams::Editor.update_business_team(
        business: @business,
        team_slug: @team.slug,
        team_name: "New Team",
        description: "New Description",
        organization_selection_type: :all
      )
    end
  end

  test "bulk delete business teams" do
    team1 = create(:business_team, business: @business, name: "team 1")
    team2 = create(:business_team, business: @business, name: "team 2")
    team3 = create(:business_team, business: @business, name: "team 3") # This team won't be deleted

    EnterpriseTeams::Editor.bulk_delete_business_teams(
      business: @business,
      team_slugs: %w[team-1 team-2]
    )

    assert_nil BusinessTeam.find_by(slug: "team-1")
    assert_nil BusinessTeam.find_by(slug: "team-2")
    refute_nil BusinessTeam.find_by(slug: "team-3") # Ensure this team still exists
  end

  test "bulk delete business teams with more than max deletions raises" do
    EnterpriseTeams::Editor.stub_const(:MAX_DELETIONS, 2) do
      team_names = (1..EnterpriseTeams::Editor::MAX_DELETIONS + 1).map { |i| "team-#{i}" }
      team_names.each { |name| create(:business_team, business: @business, name: name) }

      assert_raises(ArgumentError) do
        EnterpriseTeams::Editor.bulk_delete_business_teams(
          business: @business,
          team_slugs: team_names.map { |name| name.parameterize }
        )
      end
    end
  end

  test "bulk delete business teams with non-existent team raises" do
    team1 = create(:business_team, business: @business, slug: "team-1")

    assert_raises(ActiveRecord::RecordNotFound) do
      EnterpriseTeams::Editor.bulk_delete_business_teams(
        business: @business,
        team_slugs: %w[team-1 non-existent-slug]
      )
    end
  end

  test "bulk delete business teams with unexpected error raises error" do
    team1 = create(:business_team, business: @business, slug: "team-1")
    team2 = create(:business_team, business: @business, slug: "team-2")

    BusinessTeam.stubs(:delete_all).raises(StandardError, "Unexpected error")

    assert_raises(StandardError, "Unexpected error") do
      EnterpriseTeams::Editor.bulk_delete_business_teams(
        business: @business,
        team_slugs: %w[team-1 team-2]
      )
    end
  end

  test "organization_ids for selected" do
    team = create(:business_team, business: @business, organization_selection_type: :selected)
    team.add_to_organizations(org_ids: [@organization1.id, @organization2.id])
    assert_equal [@organization1.id, @organization2.id], team.reload.organization_ids
  end

  test "organization_ids for all_orgs" do
    team = create(:business_team, business: @business, organization_selection_type: :all)
    assert_equal @business.organization_ids, team.reload.organization_ids
  end

  test "organization_ids for no_orgs" do
    team = create(:business_team, business: @business, organization_selection_type: :disabled)
    assert_empty team.reload.organization_ids
  end
end
