# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningOrganizationUpgradePerRepositoryJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @user = create :user
    @org = create :organization, admin: @user
    @repo = create(:repository, owner: @org)

    on_multi_tenant_enterprise do
      @mt_user = create(:emu)
      @mt_business = @mt_user.enterprise_managed_business
      @mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: @mt_business, admin: @mt_user
      @mt_repo = create(:private_repository, owner: @mt_org)
    end
  end

  test "publishes featuretoggled event" do
    SecurityOverviewAnalytics::Helpers.stubs(:instrument_analytics_enablement_events?).returns(true)

    message = {
      repository_id: @repo.id,
    }

    perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationUpgradePerRepository", queue: "hydro_secret_scanning_organization_upgrade_per_repository")

    assert_hydro_published({
      repository_id: @repo.id,
      feature_enabled: false
    }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
  end

  test "publishes featuretoggled event with resolved tenant" do
    on_multi_tenant_enterprise do
      SecurityOverviewAnalytics::Helpers.stubs(:instrument_analytics_enablement_events?).returns(true)

      message = {
        repository_id: @mt_repo.id,
      }

      perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationUpgradePerRepository", queue: "hydro_secret_scanning_organization_upgrade_per_repository")

      assert_hydro_published({
        repository_id: @mt_repo.id,
        feature_enabled: false
      }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
    end
  end
end
