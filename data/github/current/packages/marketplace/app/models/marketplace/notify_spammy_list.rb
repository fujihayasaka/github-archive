
# typed: true
# frozen_string_literal: true

module Marketplace::NotifySpammyList
  include Marketplace::FinancialOnboardingDependency
  DELIST_SPAMMY_LISTING_ISSUE_NUMBER = 2350

  # Public: Creates issue to delete the subscribers and apps in marketplace for the spammy users/org, once they are marked as spammy.
  def initiate_spammy_listing_notifications(listing)
    created_issue_id = self.create_issue_in_marketplace("spammy_listing", listing.name, listing.slug)
  end

end
