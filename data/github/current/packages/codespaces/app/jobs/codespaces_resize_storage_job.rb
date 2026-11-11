# typed: true
# frozen_string_literal: true

class CodespacesResizeStorageJob < CodespacesJob
  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on Codespaces::ResizeStorage::EnvNotSuspendedError, attempts: 2
  retry_on Codespaces::ResizeStorage::EnvStillSuspendingError, wait: :polynomially_longer, attempts: 10
  locked_by timeout: 10.minutes, key: ->(job) { "codespace-#{job.arguments[0]}" }

  class ResizeTimeoutError < StandardError; end

  def perform(codespace_id:, new_sku_name:, retries_remaining: 30, operation: nil)
    codespace = Codespace.find_by(id: codespace_id)
    return unless codespace

    begin
      Codespaces::ResizeStorage.call(codespace, new_sku_name, operation: operation)
    rescue Codespaces::ResizeStorage::EnvNotSuspendedError
      # We need to skip this check since we are preforming the operation that
      # would otherwise block a suspend
      Codespace.throttle_with_retry { Codespaces::SuspendEnvironment.call(codespace, skip_async_operation_check: true) }
      raise
    end
  end
end
