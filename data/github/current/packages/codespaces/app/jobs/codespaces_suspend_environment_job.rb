# typed: true
# frozen_string_literal: true

class CodespacesSuspendEnvironmentJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  USAGE_LIMITS_REACHED_REASON = "usage_limits_reached"

  def perform(codespace:, ignore_deleted: false, suspension_reason: nil)
    with_read do
      Codespace.throttle_with_retry { codespace.suspend!(ignore_deleted: ignore_deleted) }

      if suspension_reason
        GitHub.dogstats.increment("codespaces.codespace_suspended.count", tags: ["reason:#{suspension_reason}"])
      end
    end
  rescue Codespaces::AsyncOperation::PendingError
    # We can ignore pending async operations while trying to suspend in the
    # background like this. The final state of the async operation should be
    # "Shutdown", so it will eventually be suspended, but while the async
    # operation is pending, we can't request a suspend.
  end
end
