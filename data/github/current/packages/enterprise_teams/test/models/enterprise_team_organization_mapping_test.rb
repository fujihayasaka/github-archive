# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamOrganizationMappingTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  include AuditLog::IntegrationTestHelpers

  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @business = create :global_business
      @provider = create :business_saml_provider, business: @business
      @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
      @owner = @business.owners.first
    else
      @owner = create :emu, :owner
      @business = @owner.enterprise_managed_business
    end

    @organization = create :organization, business: @business
    @org_team = create :team, organization: @organization
    @enterprise_team = create :enterprise_team, business: @business
    @enterprise_team_organization_mapping = EnterpriseTeamOrganizationMapping.create!(enterprise_team: @enterprise_team, organization: @organization)
  end

  setup do
    if GitHub.single_business_environment?
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
    end
  end

  test ".job_restraint_lock! yields to block if lock can be acquired" do
    return_value = 123
    assert_equal return_value, EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: 2) { return_value }
  end

  test ".job_restraint_lock! acquires lock when another is locked on a different enterprise team id" do
    EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: 1) do
      assert EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: 2) { true }
    end
  end

  test ".job_restraint_lock! raises GitHub::Restraint::UnableToLock if lock is locked" do
    assert_raises GitHub::Restraint::UnableToLock do
      EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: 1) do
        EnterpriseTeamOrganizationMapping.job_restraint_lock!(enterprise_team_id: 1) { true }
      end
    end
  end

  test "validates presence of enterprise_team_id" do
    @enterprise_team_organization_mapping.enterprise_team_id = nil
    refute_predicate @enterprise_team_organization_mapping, :valid?
  end

  test "validates presence of organization" do
    @enterprise_team_organization_mapping.organization = nil
    refute_predicate @enterprise_team_organization_mapping, :valid?
  end

  test "belongs to enterprise_team" do
    assert_equal @enterprise_team, @enterprise_team_organization_mapping.enterprise_team
  end

  test "belongs to organization" do
    assert_equal @organization, @enterprise_team_organization_mapping.organization
  end

  test "team defaults to nil" do
    assert_nil @enterprise_team_organization_mapping.team
  end

  test "can access team if the mapping has one" do
    @enterprise_team_organization_mapping.team = @org_team
    assert_equal @org_team, @enterprise_team_organization_mapping.team
  end

  test "enforces uniqueness on enterprise team and organization pairings" do
    assert_raises ActiveRecord::RecordInvalid do
      EnterpriseTeamOrganizationMapping.create!(enterprise_team: @enterprise_team, organization: @organization)
    end
  end

  test "status defaults to unsynced" do
    assert_equal "unsynced", @enterprise_team_organization_mapping.status
  end

  test "destroying mapping destroys the org team" do
    assert Team.find_by(id: @org_team.id)
    @enterprise_team_organization_mapping.team = @org_team
    @enterprise_team_organization_mapping.destroy!
    refute Team.find_by(id: @org_team.id)
  end

  test "destroying mapping does not create audit logs for team destroy" do
    GitHub.stubs(:esm_enabled?).returns(true)
    EnterpriseTeam.stubs(:enabled_for_organizations?).returns(true)
    assert_performed_audit_entries(count: 0, only: "team.destroy") do
      perform_enqueued_jobs(only: [DestroyTeamDependantsJob]) do
        @enterprise_team_organization_mapping.team = @org_team
        @enterprise_team_organization_mapping.destroy!
      end
    end
  end
end
