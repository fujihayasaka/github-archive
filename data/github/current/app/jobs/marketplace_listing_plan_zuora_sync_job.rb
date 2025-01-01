# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class MarketplaceListingPlanZuoraSyncJob < ApplicationJob
  queue_as :zuora

  ::Billing::Zuora::RETRYABLE_ERRORS.each do |error|
    retry_on(error, wait: :polynomially_longer) do |_job, error|
      Failbot.report(error)
    end
  end

  def perform(listing_plan)
    listing_plan.sync_to_zuora
  end
end
