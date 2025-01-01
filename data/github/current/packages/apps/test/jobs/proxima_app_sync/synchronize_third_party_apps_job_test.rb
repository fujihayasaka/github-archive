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
    test "calls orchestrate" do
      ProximaAppSync::SynchronizeJobOrchestrator.expects(:orchestrate).with(ProximaAppHelper::THIRD_PARTY_TYPE)
      ProximaAppSync::SynchronizeThirdPartyAppsJob.perform_now
    end
  end
end
