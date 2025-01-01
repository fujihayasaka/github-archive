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
