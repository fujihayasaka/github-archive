# typed: true
# frozen_string_literal: true

require "test_helper"

class BusinessSecurityCenterDependencyTest < GitHub::TestCase
  fixtures do
    @business = create(:global_business)
  end

  context "#trigger_security_center_reconciliation" do
    test "queues business reconciliation" do
      @business.trigger_security_center_reconciliation
      assert_enqueued_jobs(2, only: SecurityCenter::BusinessReconciliationJob)
      assert_enqueued_with(job: SecurityCenter::BusinessReconciliationJob, args: [{
        business_id: @business.id,
        source_event: SecurityCenter::BusinessReconciliationJob::RECONCILIATION_EVENT,
        entity_type: SecurityCenter::BusinessReconciliationJob::EntityType::Organization,
      }])
      assert_enqueued_with(job: SecurityCenter::BusinessReconciliationJob, args: [{
        business_id: @business.id,
        source_event: SecurityCenter::BusinessReconciliationJob::RECONCILIATION_EVENT,
        entity_type: SecurityCenter::BusinessReconciliationJob::EntityType::User,
      }])
    end

    test "does not error if fails to enqueue job" do
      SecurityCenter::BusinessReconciliationJob.expects(:perform_later).raises(Redis::CannotConnectError.new "boom")
      assert_nothing_raised do
        @business.trigger_security_center_reconciliation
      end
    end
  end
end
