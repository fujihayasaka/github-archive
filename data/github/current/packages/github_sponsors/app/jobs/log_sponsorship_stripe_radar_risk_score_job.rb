# typed: true
# frozen_string_literal: true

class LogSponsorshipStripeRadarRiskScoreJob < ApplicationJob
  extend T::Sig

  queue_as :stripe

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  sig { params(webhook: Billing::StripeWebhook).void }
  def perform(webhook)
    return unless GitHub.sponsors_enabled?

    SponsorshipStripeRadarRiskScore.throttle_writes_with_retry do
      SponsorshipStripeRadarRiskScore.create_from_webhook(webhook)
    end
  end
end
