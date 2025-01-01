# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesSuspendEnvironmentJobTest < GitHub::TestCase
  include JobTestHelper
  include DogstatsTestHelpers

  fixtures do
    @codespace = create(:codespace)
  end

  test "has a lock" do
    job1 = CodespacesSuspendEnvironmentJob.new(codespace: @codespace)
    job2 = CodespacesSuspendEnvironmentJob.new(codespace: @codespace)
    job3 = CodespacesSuspendEnvironmentJob.new(codespace: create(:codespace))

    assert_equal job1.lock_key, job2.lock_key
    refute_equal job1.lock_key, job3.lock_key
  end

  test "it calls Codespaces::SuspendEnvironment" do
    Codespaces::SuspendEnvironment.expects(:call).with(@codespace, equals({ user: nil, ignore_deleted: false }))
    CodespacesSuspendEnvironmentJob.perform_now(codespace: @codespace)
  end

  test "passes through the ignore_deleted option" do
    Codespaces::SuspendEnvironment.expects(:call).with(@codespace, equals({ user: nil, ignore_deleted: true }))
    CodespacesSuspendEnvironmentJob.perform_now(codespace: @codespace, ignore_deleted: true)
  end

  test "it records metrics when suspension_reason provided" do
    Codespaces::SuspendEnvironment.expects(:call).with(@codespace, equals({ user: nil, ignore_deleted: true }))
    CodespacesSuspendEnvironmentJob.perform_now(
      codespace: @codespace,
      ignore_deleted: true,
      suspension_reason: CodespacesSuspendEnvironmentJob::USAGE_LIMITS_REACHED_REASON
    )

    assert_equal 1, GitHub.dogstats.increments("codespaces.codespace_suspended.count").length
    assert_includes GitHub.dogstats.increments("codespaces.codespace_suspended.count").first.tags, "reason:usage_limits_reached"
  end

  test "it does not record metrics when suspension_reason is not provided" do
    Codespaces::SuspendEnvironment.expects(:call).with(@codespace, equals({ user: nil, ignore_deleted: true }))
    CodespacesSuspendEnvironmentJob.perform_now(codespace: @codespace, ignore_deleted: true)

    assert_equal 0, GitHub.dogstats.increments("codespaces.codespace_suspended.count").length
  end

  test "retries on a dirty exit" do
    assert_retry_on_dirty_exit job: CodespacesSuspendEnvironmentJob
  end

  test "ignores failure appropriately when codespace has pending async operations" do
    create(:codespaces_async_operation, codespace: @codespace)
    CodespacesSuspendEnvironmentJob.perform_now(codespace: @codespace)
  end
end unless GitHub.enterprise?
