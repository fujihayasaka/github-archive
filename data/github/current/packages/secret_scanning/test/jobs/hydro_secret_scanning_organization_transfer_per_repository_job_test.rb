# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSecretScanningOrganizationTransferPerRepositoryJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers
  include HydroTestHelpers

  setup do
    @user = create :user
    @org = create :organization, admin: @user
    @repo = create(:repository, owner: @org)
  end

  test "publishes featuretoggled event" do
    SecurityOverviewAnalytics::Helpers.stubs(:instrument_analytics_enablement_events?).returns(true)

    message = {
      repository_id: @repo.id,
    }

    perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationTransferPerRepository", queue: "hydro_secret_scanning_organization_transfer_per_repository")

    assert_hydro_published({
      repository_id: @repo.id,
      feature_enabled: false
    }, schema: "github.secret_scanning.v1.SecretScanningFeatureToggled")
  end
end
