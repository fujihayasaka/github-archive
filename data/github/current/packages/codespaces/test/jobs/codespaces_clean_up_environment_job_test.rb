# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesCleanUpEnvironmentJobTest < GitHub::TestCase
  include JobTestHelper

  test "has a lock" do
    job1 = CodespacesCleanUpEnvironmentJob.new(plan_id: 1, codespace_guid: 1)
    job2 = CodespacesCleanUpEnvironmentJob.new(plan_id: 1, codespace_guid: 1)
    job3 = CodespacesCleanUpEnvironmentJob.new(plan_id: 2, codespace_guid: 2)

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "it calls Codespaces::CleanUpEnvironment" do
    Codespaces::CleanUpEnvironment.expects(:call).with(plan_id: 1, codespace_guid: 1, vscs_target: :production, location: nil)
    CodespacesCleanUpEnvironmentJob.perform_now(plan_id: 1, codespace_guid: 1, vscs_target: :production)
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: CodespacesCleanUpEnvironmentJob
  end
end unless GitHub.enterprise?
