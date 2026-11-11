# typed: true
# frozen_string_literal: true

class CodespacesDeleteJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC

  retry_on Codespaces::Error, wait: :polynomially_longer, attempts: 3 do |job, error|
    job.perform(**job.arguments.first.merge(skip_vscs: true))
    logger.error "Stopped retrying CodespacesDeleteJob due to a #{error.class} after exhausting retry attempts. The original exception was #{error.cause.inspect}."
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  discard_on ActiveJob::DeserializationError

  def perform(codespace:, reason: Codespace.deletion_reasons[:user_requested], skip_vscs: false)
    if codespace&.soft_deletable?
      with_write do
        Codespace.throttle_with_retry { Codespaces::SoftDelete.call(codespace, reason: reason, skip_vscs: skip_vscs) }
      end
    else
      with_write do
        Codespace.throttle_with_retry { Codespaces::HardDelete.call(codespace, reason: reason, skip_vscs: skip_vscs) }
      end
    end
  end
end
