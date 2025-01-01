# typed: strict
# frozen_string_literal: true

class DestroyAuthenticationTokensJob < ApplicationJob
  queue_as :background_destroy

  locked_by timeout: 1.hour, key: DEFAULT_LOCK_PROC

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
  retry_on ActiveRecord::AdapterTimeout
  retry_on ActiveRecord::ConnectionFailed
  retry_on ActiveRecord::ConnectionNotEstablished
  retry_on Freno::Throttler::WaitedTooLong, wait: :polynomially_longer, attempts: 15

  sig { params(authenticatable_id: Integer, authenticatable_class: T.nilable(String)).void }
  def perform(authenticatable_id, authenticatable_class)
    total_records = ServerToServerTokens.domain.count_by_authenticatable_id(authenticatable_id)

    if total_records.nil?
      GitHub.dogstats.increment("authentication_tokens.to_destroy.count_missing", tags: ["authenticatable_class:#{authenticatable_class}"])
      return
    end

    GitHub.dogstats.distribution("authentication_tokens.to_destroy.total", total_records, tags: ["authenticatable_class:#{authenticatable_class}"])

    result = ServerToServerTokens.domain.destroy_by_authenticatable_id(authenticatable_id)
    if result.is_a?(GH::Result::Ok)
      deleted_count = result.value
      missing_deletes = total_records - deleted_count
      GitHub.dogstats.distribution("authentication_tokens.destroyed.total", deleted_count, tags: ["authenticatable_class:#{authenticatable_class}"])
      if missing_deletes.positive?
        GitHub.dogstats.distribution("authentication_tokens.destroy.partial", missing_deletes, tags: ["authenticatable_class:#{authenticatable_class}"])
      end
    end
  ensure
    GitHub.logger.info("DestroyAuthenticationTokensJob", {
      authenticatable_id: authenticatable_id,
      authenticatable_class: authenticatable_class,
      expected_to_delete: total_records,
      actually_deleted: deleted_count || 0
    })
  end
end
