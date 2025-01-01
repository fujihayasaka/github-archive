# typed: true
# frozen_string_literal: true

module TradeControls
  module Sdn
    # This job checks that a profile has been suspended after a true match screening status is received
    # Suspension is carried out by support but this is a catch for missed signals
    class TrueMatchSuspendedCheckJob < ApplicationJob
      queue_as :trade_screening
      retry_on_dirty_exit

      # Ensure that the enqueued job is performed some time after the true match status is received
      def self.enqueue(id)
        self.set(wait: 7.days).perform_later(id)
      end

      def perform(id)
        profile = AccountScreeningProfile.find_by(id: id)
        return unless profile&.true_match?
        return if T.must(profile.owner.sdn_suspended?)
        return if T.must(profile.last_trade_screen_date) > 7.days.ago

        GitHub.dogstats.increment(
          "sdn.status.not_suspended",
          tags: ["status:true_match"]
        )
      end
    end
  end
end
