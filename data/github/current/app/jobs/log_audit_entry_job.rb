# typed: true
# frozen_string_literal: true

class LogAuditEntryJob < ApplicationJob
  LOGGER_MAX_RETRIES = 20 # Matching previous legacy job behavior.
  LOGGER_EXCEPTIONS = [
    ElastomerClient::Client::Error,
  ]

  queue_as :audit_logs

  retry_on_recoverable_exceptions
  retry_on_dirty_exit
  retry_on(*LOGGER_EXCEPTIONS, attempts: LOGGER_MAX_RETRIES)

  def self.allow_async_enqueues?
    false
  end

  def perform(action, payload = {})
    GitHub.audit.log_payload(action: action, payload: payload.dup, on_error_behavior: :raise)
  end
end
