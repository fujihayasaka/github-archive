# typed: true
# frozen_string_literal: true
require "test_helper"

class OrganizationTeamSyncTest < GitHub::TestCase
  fixtures do
    @provider = create(:organization_saml_provider)
    @org = @provider.organization
  end

  context "Organization#team_sync_feature_available?" do
    test "returns false for Enterprise", enterprise_only: true do
      refute_predicate @org, :team_sync_feature_available?
    end

    test "returns true when SSO is present and presisted" do
      assert_predicate @org, :team_sync_feature_available?
    end

    test "returns false when organization is not under a business plan" do
      org = create(:organization)
      refute_predicate org, :team_sync_feature_available?
    end
  end

  context "Organization#async_team_sync_enabled?" do
    test "false if org is business-owned, but business doesn't have saml sso enabled" do
      org_in_business = create(:organization)
      business = create :business, organizations: [org_in_business]

      refute org_in_business.async_team_sync_enabled?.sync
    end

    test "false if org is owned by team-sync-enabled business, but has no tenant" do
      org_in_business = create(:organization)
      business = create :business, organizations: [org_in_business]
      create :business_team_sync_tenant, business: business

      refute org_in_business.async_team_sync_enabled?.sync
    end

    test "false if org is owned by team-sync-enabled business, but org tenant not enabled" do
      org_tenant = create :team_sync_tenant, status: :disabled
      org_in_business = org_tenant.organization
      business = create :business, organizations: [org_in_business]
      create :business_team_sync_tenant, business: business

      refute org_in_business.async_team_sync_enabled?.sync
    end

    test "true if org is owned by team-sync-enabled business and its own tenant is enabled" do
      org_tenant = create :team_sync_tenant
      org_in_business = org_tenant.organization
      business = create :business, organizations: [org_in_business]
      create :business_team_sync_tenant, business: business

      assert org_in_business.async_team_sync_enabled?.sync
    end
  end

  context "Organization#team_sync_failed_teams" do
    test "returns teams from the org whose tenants contain at least one mapping that failed to sync" do
      org = create(:business_plus_org)
      team1 = create(:team, organization: org, name: "team1")
      team2 = create(:team, organization: org, name: "team2")
      team3 = create(:team, organization: org, name: "team3")
      team4 = create(:team, organization: org, name: "team4")

      saml_provider = create(:organization_saml_provider, organization: org, issuer: "https://sts.windows.net/a3350e2e-d5fb-4682-b8ed-5cf081a1e841/")
      tenant = create :team_sync_tenant, organization: org
      create :team_group_mapping, tenant: tenant, team: team1, status: :synced
      create :team_group_mapping, tenant: tenant, team: team1, status: :failed
      create :team_group_mapping, tenant: tenant, team: team2, status: :failed
      create :team_group_mapping, tenant: tenant, team: team3, status: :synced

      assert_same_elements [team1, team2], org.team_sync_failed_teams
    end

    test "returns empty scope if team sync was never enabled (that is, there is no tenant)" do
      org = create(:business_plus_org)

      assert_empty org.team_sync_failed_teams
    end
  end
end if GitHub.team_synchronization_available?
