# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SynchronizeThirdPartyAppsJobTest < GitHub::TestCase
  include JobTestHelper

  context "#retry_on_dirty_exit" do
    test "retry conditions" do
      assert_retry_on_dirty_exit job: ProximaAppSync::SynchronizeThirdPartyAppsJob
    end
  end

  context "schedule" do
    test "default schedule time is 5 minutes" do
      job = ProximaAppSync::SynchronizeThirdPartyAppsJob
      assert_equal 5.minutes, job.schedule_options[:interval]
    end
  end

  context "#perform" do
    test "calls orchestrate when FF enabled" do
      ProximaAppSync::SynchronizeJobOrchestrator.expects(:orchestrate).with(ProximaAppHelper::THIRD_PARTY_TYPE)
      GitHub.flipper[:proxima_third_party_app_synchronizations].enable
      ProximaAppSync::SynchronizeThirdPartyAppsJob.perform_now
    end

    test "doesn't call orchestrate when FF disabled" do
      ProximaAppSync::SynchronizeJobOrchestrator.expects(:orchestrate).with(ProximaAppHelper::THIRD_PARTY_TYPE).never
      GitHub.flipper[:proxima_third_party_app_synchronizations].disable
      ProximaAppSync::SynchronizeThirdPartyAppsJob.perform_now
    end
  end
end
