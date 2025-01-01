# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class SynchronizeFirstPartyAppsJobTest < GitHub::TestCase
  include JobTestHelper

  context "#retry_on_dirty_exit" do
    test "retry conditions" do
      assert_retry_on_dirty_exit job: ProximaAppSync::SynchronizeFirstPartyAppsJob
    end
  end

  context "schedule" do
    test "default schedule time is 5 minutes" do
      job = ProximaAppSync::SynchronizeFirstPartyAppsJob
      assert_equal 5.minutes, job.schedule_options[:interval]
    end
  end

  context "#perform" do
    test "calls orchestrate" do
      ProximaAppSync::SynchronizeJobOrchestrator.expects(:orchestrate).with(ProximaAppHelper::FIRST_PARTY_TYPE)
      ProximaAppSync::SynchronizeFirstPartyAppsJob.perform_now
    end
  end
end
