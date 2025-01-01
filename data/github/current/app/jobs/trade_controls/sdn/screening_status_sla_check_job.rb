# typed: strict
# frozen_string_literal: true
# This job is queued up anytime a profile is update with a "hit_in_review" screening status.
class TradeControls::Sdn::ScreeningStatusSlaCheckJob < ApplicationJob

  queue_as :trade_screening
  retry_on_dirty_exit

  sig { params(id: Integer).returns(TradeControls::Sdn::ScreeningStatusSlaCheckJob) }
  def self.enqueue(id)
    self.set(wait: 3.days).perform_later(id)
  end

  sig { params(id: Integer).void }
  def perform(id)
    profile = AccountScreeningProfile.find_by(id: id)
    return unless profile.present?
    return unless profile.hit_in_review?
    return if profile.last_trade_screen_date >= 3.days.ago

    # Rescreen the profile to check if there has been an update that has not come through EIS poll job
    # This will also update the profiles "rescreen_reason" to SLA breach
    profile.rescreen_on_sla_breach
    return unless profile.hit_in_review?

    GitHub.dogstats.increment(
      "sdn.status.sla_breached",
      tags: ["status:hit_in_review"]
    )

    TradeScreeningMailer.trade_screening_48_hour_sla_breach(profile.external_uuid).deliver_later
  end
end
