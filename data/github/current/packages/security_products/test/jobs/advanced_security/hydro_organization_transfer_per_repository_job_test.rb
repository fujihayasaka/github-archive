# typed: true
# frozen_string_literal: true

require "test_helper"

module AdvancedSecurity
  class HydroOrganizationTransferPerRepositoryJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers

    setup do
      @queue = HydroOrganizationTransferPerRepositoryJob.queue_name
      @user = create :user
      @org = create :organization, admin: @user
      @repo = create(:repository, owner: @org)
    end

    test "publishes featuretoggled event" do
      SecurityOverviewAnalytics::Helpers.stubs(:instrument_analytics_enablement_events?).returns(true)

      message = {
        repository_id: @repo.id,
      }

      perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationTransferPerRepository", queue: @queue)

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: false
      }, schema: "github.security_center.v0.AdvancedSecurityToggled")
    end
  end
end
