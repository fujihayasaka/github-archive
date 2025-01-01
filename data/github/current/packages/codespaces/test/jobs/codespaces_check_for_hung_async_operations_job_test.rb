# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/job_test_helper"

class CodespacesCheckForHungAsyncOperationsJobTest < GitHub::TestCase
  include DogstatsTestHelpers
  include JobTestHelper

  test "doesn't queue up timeout job if op is finished" do
    create(:codespaces_async_operation, :finished)

    assert_enqueued_jobs 0, only: CodespacesAsyncOperationSyncStateJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "donsn't queue up timeout job if op hasn't run long enough" do
    create(:codespaces_async_operation, op_started_at: 2.minutes.ago)

    assert_enqueued_jobs 0, only: CodespacesAsyncOperationSyncStateJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up sync state job if unfinished op has been running long enough without timeout value" do
    create(:codespaces_async_operation, op_started_at: 11.minutes.ago)

    assert_enqueued_jobs 1, only: CodespacesAsyncOperationSyncStateJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up sync state job if unfinished op has been running long enough before timeout value" do
    create(:codespaces_async_operation, op_started_at: 11.minutes.ago, operation: :start_codespace)

    assert_enqueued_jobs 1, only: CodespacesAsyncOperationSyncStateJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up timeout job if unfinished op has been running long enough" do
    create(:codespaces_async_operation, op_started_at: 110.minutes.ago, operation: :start_codespace)

    assert_enqueued_jobs 1, only: CodespacesAsyncOperationTimeoutJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up timeout job if unstarted op has been unstarted long enough" do
    create(:codespaces_async_operation, created_at: 6.minutes.ago)

    assert_enqueued_jobs 1, only: CodespacesAsyncOperationTimeoutJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up a timeout job for each unfinished op that has been running long enough" do
    unfinished_op_count = 10
    create_list(:codespaces_async_operation, unfinished_op_count, op_started_at: 110.minutes.ago, operation: :start_codespace)

    assert_enqueued_jobs unfinished_op_count, only: CodespacesAsyncOperationTimeoutJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up correct jobs for ops in different states" do
    create(:codespaces_async_operation, op_started_at: 110.minutes.ago, operation: :start_codespace)
    create(:codespaces_async_operation, op_started_at: 11.minutes.ago, operation: :start_codespace)

    assert_enqueued_jobs 2, only: [CodespacesAsyncOperationTimeoutJob, CodespacesAsyncOperationSyncStateJob] do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up a sync state job for each unfinished op that has been running long enough before timeout value" do
    unfinished_op_count = 10
    unfinished_op_count.times do
      create(:codespaces_async_operation, op_started_at: 11.minutes.ago, operation: :start_codespace)
    end

    assert_enqueued_jobs unfinished_op_count, only: CodespacesAsyncOperationSyncStateJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "queues up a sync state job for each unfinished op that has been running long enough without timeout value" do
    unfinished_op_count = 10
    unfinished_op_count.times do
      create(:codespaces_async_operation, op_started_at: 11.minutes.ago)
    end

    assert_enqueued_jobs unfinished_op_count, only: CodespacesAsyncOperationSyncStateJob do
      CodespacesCheckForHungAsyncOperationsJob.perform_now
    end
  end

  test "captures the ongoing jobs count in datadog with flag" do
    unfinished_op_count = 10
    unfinished_op_count.times do
      create(:codespaces_async_operation, op_started_at: 11.minutes.ago)
    end

    CodespacesCheckForHungAsyncOperationsJob.perform_now

    assert_dogstats_count_value(10, "codespaces.async_operations.ongoing_jobs", tags: ["operation:update_storage"])
  end

  test "captures the hung jobs count in datadog" do
    unfinished_op_count = 10
    unfinished_op_count.times do
      create(:codespaces_async_operation, op_started_at: 110.minutes.ago, operation: :start_codespace)
    end

    CodespacesCheckForHungAsyncOperationsJob.perform_now

    assert_dogstats_count_value(10, "codespaces.async_operations.hung_jobs", tags: ["operation:start_codespace"])
  end
end unless GitHub.enterprise?
