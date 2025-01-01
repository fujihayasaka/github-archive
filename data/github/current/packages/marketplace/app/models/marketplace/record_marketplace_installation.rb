# typed: true
# frozen_string_literal: true

module Marketplace
  class RecordMarketplaceInstallation
    def self.call(user:, application:)
      # we look up purchases by the user and by the user's orgs that allow the app
      allowed_org_ids = user.organizations.select { |org| org.allows_oauth_application?(application) }.map(&:id)
      account_ids = [user.id, allowed_org_ids].flatten

      marketplace_listing_plans_ids = Marketplace::ListingPlan.joins(:listing)
        .where(marketplace_listings: {
          listable_id: application.id,
          listable_type: Marketplace::Listing::OAUTH_APPLICATION_TYPE,
        }).pluck(:id)

      Billing::SubscriptionItem.for_users_on_marketplace_listing_plans(
        user_ids: account_ids,
        listing_plans_ids: marketplace_listing_plans_ids,
      ).each do |sub_item|
        ActiveRecord::Base.connected_to(role: :writing) do
          sub_item.record_marketplace_installation
        end
      end
    end
  end
end
