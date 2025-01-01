# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroOrganizationAddJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @queue = HydroOrganizationAddJob.queue_name
      @schema = "github.enterprise_account.v0.OrganizationAdd"
      @org = create(:organization)
    end

    context "#perform" do
      test "kicks off initialization job for the organization" do
        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 1, only: Initialization::OrganizationJob do
          perform_hydro_message_job({
            organization: serialized_org,
          }, schema: @schema, queue: @queue)
        end
      end

      test "kicks off reconciliation job for the organization if it was previously initialized" do
        Initialization.for(@org).set_all_to_initialized

        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 1, only: Reconciliation::OrganizationReconciliationJob do
          perform_hydro_message_job({
            organization: serialized_org,
          }, schema: @schema, queue: @queue)
        end
      end

      test "kicks off fanout jobs for the organization" do
        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 2, only: Fanout::RepositoryOwnerJob do
          perform_hydro_message_job({
            organization: serialized_org,
          }, schema: @schema, queue: @queue)
        end
      end

      test "raises error and retries if organization doesn't exist" do
        Organization.stubs(:find_by).with(id: @org.id).returns(nil)
        HydroOrganizationAddJob.any_instance.expects(:retry).once.with(
          responds_with(
            :message,
            "Organization with ID #{@org.id} not found, retrying",
          ),
          delay: 2.0,
        )

        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 0, only: Initialization::OrganizationJob do
          perform_hydro_message_job({
            organization: serialized_org,
          }, schema: @schema, queue: @queue)
        end
      end

      test "silently stops the job after max number of retries" do
        Organization.stubs(:find_by).with(id: @org.id).returns(nil)
        HydroOrganizationAddJob.any_instance.expects(:retry).never
        HydroMessageJob.any_instance.stubs(:retries).returns(10)

        serialized_org = Hydro::EntitySerializer.organization(@org)

        assert_enqueued_jobs 0, only: Initialization::OrganizationJob do
          perform_hydro_message_job({
            organization: serialized_org,
          }, schema: @schema, queue: @queue)
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

          Organization.expects(:find_by!).with(id: mt_org.id).returns(mt_org)

          serialized_org = Hydro::EntitySerializer.organization(mt_org)
          assert_enqueued_jobs 1, only: Initialization::OrganizationJob do
            perform_hydro_message_job({
              organization: serialized_org,
            }, schema: @schema, queue: @queue)
          end
        end
      end
    end
  end
end
