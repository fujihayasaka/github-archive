# typed: true
# frozen_string_literal: true

# Check if a codespace is still inaccessible. If it is, then deprovision it.
class Codespaces::CleanUpInaccessibleJob < CodespacesJob
  locked_by timeout: 7.days, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  discard_on ActiveJob::DeserializationError

  def perform(codespace:, reason: Codespace.deletion_reasons[:inaccessible])
    # If the codespace became accessible again during the waiting period then we
    # don't need to do anything
    if codespace.accessible?
      GitHub.dogstats.increment("codespaces.clean_up_inaccessible_noop")
      return
    end

    GitHub.dogstats.increment("codespaces.clean_up_inaccessible")

    Codespace.throttle_with_retry { codespace.deprovision!(reason: reason) }
  end
end
