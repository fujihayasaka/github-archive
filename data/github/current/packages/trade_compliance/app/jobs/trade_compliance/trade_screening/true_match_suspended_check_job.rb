# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  # This job checks that a profile has been suspended after a true match screening status is received
  # Suspension is carried out by support but this is a catch for missed signals
  class TrueMatchSuspendedCheckJob < ApplicationJob
    queue_as :trade_screening
    retry_on_dirty_exit

    # Ensure that the enqueued job is performed some time after the true match status is received
    sig { params(id: Integer).returns(T.self_type) }
    def self.enqueue(id)
      self.set(wait: 7.days).perform_later(id)
    end

    sig { params(id: Integer).void }
    def perform(id)
      profile = AccountScreeningProfile.find_by(id: id)
      return unless profile&.is_true_match_restricted?
      return if profile.owner.sdn_suspended?
      return if profile.last_trade_screen_date > 7.days.ago

      GitHub.dogstats.increment(
        "sdn.status.not_suspended",
        tags: ["status:true_match"]
      )
    end
  end
end
