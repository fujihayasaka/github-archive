# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesAsyncOperationTimeoutJobTest < GitHub::TestCase
  test "marks ops as ended if start times out" do
    op = create(:codespaces_async_operation, created_at: 6.minutes.ago)
    op.expects(:check_if_complete).twice.returns(false)
    CodespacesAsyncOperationTimeoutJob.perform_now(op)

    assert op.reload.op_ended_at
  end

  test "doesn't mark op as ended if it started after the job was enqueued" do
    op = create(:codespaces_async_operation, op_started_at: 1.minute.ago)
    op.expects(:check_if_complete).twice.returns(false)
    CodespacesAsyncOperationTimeoutJob.perform_now(op)

    refute op.reload.op_ended_at
  end

  test "doesn't mark op as ended if it hasn't been unstarted for long enough" do
    op = create(:codespaces_async_operation, created_at: 4.minutes.ago)
    op.expects(:check_if_complete).twice.returns(false)
    CodespacesAsyncOperationTimeoutJob.perform_now(op)

    refute op.reload.op_ended_at
  end

  test "doesn't mark op as failed if it's complete" do
    op = create(:codespaces_async_operation)
    op.expects(:check_if_complete).once.returns(true)
    op.expects(:mark_as_failed).never
    CodespacesAsyncOperationTimeoutJob.perform_now(op)
  end

  test "marks op as failed if it's not complete" do
    op = create(:codespaces_async_operation, operation: :start_codespace)
    op.update(op_started_at: (op.finish_timeout + 1.minute).ago)
    op.expects(:check_if_complete).twice.returns(false)

    op.expects(:mark_as_failed)

    CodespacesAsyncOperationTimeoutJob.perform_now(op)
  end

  test "marks op as ended not failed if it timed out but the codespace was deleted" do
    codespace = create(:codespace, :deleted)
    op = create(:codespaces_async_operation, operation: :create_codespace, codespace:)
    op.update(op_started_at: (op.finish_timeout + 1.minute).ago)
    op.expects(:check_if_complete).twice.returns(false)

    op.expects(:mark_as_ended)

    CodespacesAsyncOperationTimeoutJob.perform_now(op)
  end
end
