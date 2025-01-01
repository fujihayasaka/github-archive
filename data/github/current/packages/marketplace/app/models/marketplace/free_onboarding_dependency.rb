# typed: true
# frozen_string_literal: true

module Marketplace::FreeOnboardingDependency

  extend T::Sig
  # Public: Creates issue and enqueues Free Onboarding Job
  # listing_type - type of listing
  # listing_name - name of the marketplace listing
  # listing_slug - slug of the marketplace listing
  sig { params(listing_type: String, listing_name: String, listing_slug: String).void }
  def initiate_free_onboarding(listing_type, listing_name, listing_slug)
    FreeOnboardingJob.perform_now(listing_type, listing_name, listing_slug)
  end
end
