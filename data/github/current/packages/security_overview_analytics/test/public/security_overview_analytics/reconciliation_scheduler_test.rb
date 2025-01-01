# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

module SecurityOverviewAnalytics
  class ReconciliationSchedulerTest < GitHub::TestCase
    context ".run_for" do
      test "enqueues OrganizationReconciliationJob for an organization" do
        org = create(:organization)
        assert_enqueued_jobs 1, only: Reconciliation::OrganizationReconciliationJob do
          ReconciliationScheduler.run_for(org)
        end
      end

      test "enqueues OwnerReconciliationJob for a user" do
        user = create(:user)
        assert_enqueued_jobs 1, only: Reconciliation::OwnerReconciliationJob do
          ReconciliationScheduler.run_for(user)
        end
      end

      test "enqueues BusinessReconciliationJob for a business" do
        biz = create(:business)
        assert_enqueued_jobs 2, only: Reconciliation::BusinessReconciliationJob do
          ReconciliationScheduler.run_for(biz)
        end
      end


      test "raises for unsupported scope" do
        assert_raises do
          ReconciliationScheduler.run_for(T.unsafe(1))
        end
      end
    end
  end
end
