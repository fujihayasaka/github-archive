# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroBillingPlanChangeJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @queue = HydroBillingPlanChangeJob.queue_name
      @schema = "github.v1.BillingPlanChange"
      @org = create(:organization)
    end

    context "#perform" do
      test "kicks off initialization job for the organization" do
        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 1, only: Initialization::OrganizationJob do
          assert_enqueued_jobs 2, only: Fanout::RepositoryOwnerJob do
            perform_hydro_message_job({
              organization: serialized_org,
              action: :UPGRADE,
            }, schema: @schema , queue: @queue)
          end
        end
      end

      test "kicks off reconciliation job for the organization if it was previously initialized" do
        Initialization.for(@org).set_all_to_initialized

        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 1, only: Reconciliation::OrganizationReconciliationJob do
          perform_hydro_message_job({
            organization: serialized_org,
            action: :UPGRADE,
          }, schema: @schema , queue: @queue)
        end
      end

      test "does not kick off initialization job on downgrade" do
        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 0, only: Initialization::OrganizationJob do
          perform_hydro_message_job({
            organization: serialized_org,
            action: :DOWNGRADE,
          }, schema: @schema , queue: @queue)
        end
      end
    end

    context "on multi tenant enterprise" do
      test "resolves tenant context and performs for org from the same tenant" do
        on_multi_tenant_enterprise do
          mt_user = create(:emu)
          mt_business = mt_user.enterprise_managed_business
          GitHub::CurrentTenant.set(mt_business)
          mt_org = create :enterprise_linked_organization, :with_org_namespacing, business: mt_business, admin: mt_user

          # Simulate no tenant being set
          GitHub::CurrentTenant.remove
          assert_nil GitHub::CurrentTenant.get
          refute_predicate GitHub::CurrentTenant, :unscoped?

          Organization.expects(:find_by!).once.with(id: mt_org.id).returns(mt_org)

          serialized_org = Hydro::EntitySerializer.organization(mt_org)
          assert_enqueued_jobs 1, only: Initialization::OrganizationJob do
            perform_hydro_message_job({
              organization: serialized_org,
              action: :UPGRADE,
            }, schema: @schema , queue: @queue)
          end
        end
      end
    end
  end
end
