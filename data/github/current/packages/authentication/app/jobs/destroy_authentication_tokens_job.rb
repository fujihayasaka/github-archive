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

  sig { params(authenticatable_id: Integer, authenticatable_class: String).void }
  def perform(authenticatable_id, authenticatable_class)
    result = ServerToServerTokens.domain.destroy_by_authenticatable(authenticatable_class, authenticatable_id)

    if result.is_a?(GH::Result::Ok)
      deleted_count = result.value
      GitHub.dogstats.distribution("authentication_tokens.destroyed.total", deleted_count, tags: ["authenticatable_class:#{authenticatable_class}"])
    end
  ensure
    GitHub.logger.info("DestroyAuthenticationTokensJob", {
      authenticatable_id: authenticatable_id,
      authenticatable_class: authenticatable_class,
      actually_deleted: deleted_count || 0
    })
  end
end
