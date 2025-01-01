# typed: true
# frozen_string_literal: true

module TradeControls
  module Sdn
    class PerformTradeScreeningRetryJob < ApplicationJob
      BATCH_SIZE = 100

      queue_as :trade_screening
      retry_on_dirty_exit

      schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

      def perform
        AccountScreeningProfile.sdn_retries.limit(BATCH_SIZE).each do |upp|
          TradeScreeningRetryJob.perform_later(upp)
        end
      end
    end
  end
end
