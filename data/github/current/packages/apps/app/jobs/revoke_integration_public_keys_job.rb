# typed: true
# frozen_string_literal: true

class RevokeIntegrationPublicKeysJob < ApplicationJob
  queue_as :revoke_integration_public_keys
  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ->(job) { job.arguments.first.id }

  discard_on ActiveRecord::RecordNotFound

  BATCH_SIZE      = 10_000
  DURATION        = 60
  MAX_RETRY_COUNT = 8

  def perform(integration, enqueued_at)
    bot = integration.bot
    created_before = Time.at(enqueued_at)

    public_keys = PublicKey.where(verifier: bot).where("created_at <= ?", created_before)

    GitHub::SafeTimer.timeout(DURATION) do |timer|
      public_keys.in_batches(of: BATCH_SIZE) do |relation|
        PublicKey.throttle_with_retry(max_retry_count: MAX_RETRY_COUNT) do
          relation.each do |public_key|
            GitHub.audit.inline do
              with_write do
                public_key.destroy_with_explanation(:removed_by_staff)
              end
            end
          end
        end

        break if timer.expired?
      end
    end

    return if public_keys.none?

    clear_lock
    RevokeIntegrationPublicKeysJob.perform_later(integration, enqueued_at)
  end
end
