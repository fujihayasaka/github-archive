# typed: true
# frozen_string_literal: true

class CodespacesAsyncOperationTimeoutJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  def perform(op)
    # try to see if op is complete
    return if op.check_if_complete
    # pull in environment data and check again
    return if op.check_if_complete(force_update: true)

    if op.start_timed_out? || op.finish_timed_out?
      with_write do
        if op.codespace && op.codespace.deleted?
          # If a codespace is deleted DURING provisioning but after it was assigned a guid the service will immediately
          # delete it even though we soft delete it. We will then wait around for a webhook that will never happen because
          # the codespace was marked delted before the state was updated to shutdown. In this case we should just mark
          # the operation as ended.
          op.mark_as_ended
        else
          op.mark_as_failed(failure_reason: "AsyncOperationTimeout")
        end
      end
    end
  end
end
