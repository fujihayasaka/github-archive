# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  class PerformScreeningRetryJob < ApplicationJob
    BATCH_SIZE = 100

    queue_as :trade_screening
    retry_on_dirty_exit

    schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

    sig { void }
    def perform
      AccountScreeningProfile.sdn_retries.limit(BATCH_SIZE).each do |upp|
        RetryScreeningJob.perform_later(upp)
      end
    end
  end
end
