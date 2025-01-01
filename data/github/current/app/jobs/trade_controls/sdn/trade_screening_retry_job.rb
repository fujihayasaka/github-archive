# typed: strict
# frozen_string_literal: true

module TradeControls
  module Sdn
    class TradeScreeningRetryJob < ApplicationJob
      extend T::Sig

      queue_as :trade_screening
      retry_on_dirty_exit

      sig { params(upp: AccountScreeningProfile).void }
      def perform(upp)
        previous_status = upp.msft_trade_screening_status
        owner = upp.owner
        return unless owner.present?

        with_write do
          owner.perform_live_sdn_screening(force: true)
          owner.reload
        end

        current_status = owner.trade_screening_record.msft_trade_screening_status
        log_success(previous_status, current_status)
      end

      private

      sig { params(previous_status: String, current_status: String).void }
      def log_success(previous_status, current_status)
        return if previous_status == current_status

        GitHub.dogstats.increment(
          "sdn_trade_screening_retry_job.success",
          tags: ["status:#{current_status}"],
        )
      end
    end
  end
end
