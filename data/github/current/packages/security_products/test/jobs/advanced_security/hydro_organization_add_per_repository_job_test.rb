# typed: true
# frozen_string_literal: true

require "test_helper"

module AdvancedSecurity
  class HydroOrganizationAddPerRepositoryJobTest < GitHub::TestCase
    include HydroMessageJobTestHelpers
    include HydroTestHelpers
    include DogstatsTestHelpers

    setup do
      @queue = HydroOrganizationAddPerRepositoryJob.queue_name
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

      perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationAddPerRepository", queue: @queue)

      assert_hydro_published({
        repository_id: @repo.id,
        feature_enabled: false
      }, schema: "github.security_center.v0.AdvancedSecurityToggled")
    end

    test "publishes featuretoggled event with resolved tenant" do
      on_multi_tenant_enterprise do
        SecurityOverviewAnalytics::Helpers.stubs(:instrument_analytics_enablement_events?).returns(true)

        message = {
          repository_id: @mt_repo.id,
        }

        perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationAddPerRepository", queue: @queue)

        assert_hydro_published({
          repository_id: @mt_repo.id,
          feature_enabled: false
        }, schema: "github.security_center.v0.AdvancedSecurityToggled")
      end
    end

    test "emits metrics for published featuretoggled event with resolved tenant" do
      on_multi_tenant_enterprise do
        SecurityOverviewAnalytics::Helpers.stubs(:instrument_analytics_enablement_events?).returns(true)

        message = {
          repository_id: @mt_repo.id,
        }
        tags = [
          "tenant_set:true",
          "query_scoping:enabled",
          "job:advanced_security/hydro_organization_add_per_repository_job",
          "service:github/security_products_experiences",
          "tenant_context_requirement_temporarily_exempt:false",
          "tenant_context_requirement_exempt:false",
          "resolve_tenant_context_defined:true"
        ]

        perform_hydro_message_job(message, schema: "github.enterprise_account.v0.OrganizationAddPerRepository", queue: @queue)

        assert_hydro_published({
          repository_id: @mt_repo.id,
          feature_enabled: false
        }, schema: "github.security_center.v0.AdvancedSecurityToggled")

        assert_dogstats_increment 1, "tenant_context.hydro_message_job", tags: tags
      end
    end
  end
end
