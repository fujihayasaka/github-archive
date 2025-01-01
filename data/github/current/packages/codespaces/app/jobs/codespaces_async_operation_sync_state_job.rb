# typed: true
# frozen_string_literal: true

class CodespacesAsyncOperationSyncStateJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit

  def perform(op)
    # try to see if op is complete
    return if op.check_if_complete
    # pull in environment data and check again
    return if op.check_if_complete(force_update: true)
    # don't do anything if we haven't been told by VSCS that the state has
    # changed. This codespace will either receive a state update/webhook or
    # get tossed back to this job the next time it runs.
  end
end
