# typed: true
# frozen_string_literal: true

class SponsorsListingZuoraSyncJob < ApplicationJob
  include GitHub::Billing::ZuoraRateLimitHandler
  queue_as :zuora

  retry_on_dirty_exit

  locked_by timeout: 10.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  rescue_from(Zuorest::TooManyRequestsError) do |error|
    T.bind(self, SponsorsListingZuoraSyncJob)
    zuora_rate_limit_handler(self, error)
  end

  sig { params(sponsors_listing: SponsorsListing).void }
  def perform(sponsors_listing)
    sponsors_listing.sync_to_zuora
  end
end
