# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class Codespaces::SuspendCodespaceAtUsageLimitJobTest < GitHub::TestCase
  include JobTestHelper

  fixtures do
    @codespace_one = create(:codespace)
    @codespace_two = create(:codespace)
  end

  test "has a lock" do
    job1 = Codespaces::SuspendCodespaceAtUsageLimitJob.new(codespace: @codespace_one)
    job2 = Codespaces::SuspendCodespaceAtUsageLimitJob.new(codespace: @codespace_one)
    job3 = Codespaces::SuspendCodespaceAtUsageLimitJob.new(codespace: @codespace_two)

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "it calls Codespaces::SuspendCodespacesAtSpendingLimit" do
    Codespaces::SuspendCodespaceAtUsageLimit.expects(:call).with(codespace: @codespace_one)
    Codespaces::SuspendCodespaceAtUsageLimitJob.perform_now(codespace: @codespace_one)
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: Codespaces::SuspendCodespaceAtUsageLimitJob
  end
end unless GitHub.enterprise?
