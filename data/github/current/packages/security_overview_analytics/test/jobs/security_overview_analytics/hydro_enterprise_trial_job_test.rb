# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityOverviewAnalytics
  class HydroEnterpriseTrialJobTest < GitHub::TestCase
    include GitHub::QueryAssertionTestHelpers
    include HydroMessageJobTestHelpers

    fixtures do
      @queue = HydroEnterpriseTrialJob.queue_name
      @schema = "github.enterprise_account.v0.Trial"
      @business = create(:business)
    end

    context "#perform" do
      test "kicks off initialization job for the business" do
        runs = @business.enterprise_managed? || GitHub.enterprise? ? 2 : 1

        serialized_business = Hydro::EntitySerializer.business(@business)

        assert_enqueued_jobs runs, only: Initialization::BusinessJob do
          assert_enqueued_jobs 2, only: Fanout::BusinessJob do
            perform_hydro_message_job({
              enterprise: serialized_business,
            }, schema: @schema, queue: @queue)
          end
        end
      end
    end

    context "on multi tenant enterprise" do
      test "resolves tenant context and performs for org from the same tenant" do
        on_multi_tenant_enterprise do
          mt_user = create(:emu)
          mt_business = mt_user.enterprise_managed_business
          GitHub::CurrentTenant.set(mt_business)

          # Simulate no tenant being set
          GitHub::CurrentTenant.remove
          assert_nil GitHub::CurrentTenant.get
          refute_predicate GitHub::CurrentTenant, :unscoped?

          Business.expects(:find_by).once.with(id: mt_business.id).returns(mt_business)

          serialized_business = Hydro::EntitySerializer.business(mt_business)
          assert_enqueued_jobs 2, only: Initialization::BusinessJob do
            assert_enqueued_jobs 2, only: Fanout::BusinessJob do
              perform_hydro_message_job({
                enterprise: serialized_business,
              }, schema: @schema, queue: @queue)
            end
          end
        end
      end
    end
  end
end
