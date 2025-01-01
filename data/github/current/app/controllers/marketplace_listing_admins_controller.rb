# typed: true
# frozen_string_literal: true

class MarketplaceListingAdminsController < ApplicationController

  before_action :marketplace_required
  before_action :login_required, only: [:update]
  before_action :this_marketplace_listing_required, only: [:update]
  before_action :this_marketplace_listing_admin_required, only: [:update]

  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:update]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:update], optional: true

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "MarketplaceListingAdminsController#update"
  ]

  def update
    listing = this_marketplace_listing
    if listing.can_delist? && Marketplace::Public::update_listing(listing, inputs: { removal_date: DateTime.now }, viewer: current_user)
      target_cancellation_date = listing.removal_date.end_of_month
      listing.delist! # delists the app, changing the state of the listing to archived, hiding it from the marketplace
      MarketplaceCancelSubscriptionsJob.set(wait_until: target_cancellation_date).perform_later(listing.id) # cancels the subscription for the app at the end of the month
      MarketplaceSubscriptionCancelEmailJob.perform_now(listing.id, target_cancellation_date)
      flash[:notice] = "#{listing.name} has been successfully delisted."
      redirect_to manage_marketplace_listings_path
    else
      flash[:error] = "Marketplace listing cannot be delisted."
      redirect_to edit_marketplace_listing_path(listing.slug)
    end
  end

  private

  memoize def this_marketplace_listing
    slug = params[:id]
    return if slug.blank?

    Marketplace::Listing.find_by(slug: slug)
  end

  def resource_for_conditional_access
    # This is OK as we have before_action :login and :this_marketplace_listing_required so action will 404 if no listing
    return :no_resource_for_conditional_access if this_marketplace_listing.nil? # rubocop:disable GitHub/SpecifyResourceForConditionalAccess

    this_marketplace_listing
  end

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing
  end

  def this_marketplace_listing_admin_required
    render_404 unless this_marketplace_listing.adminable_by?(current_user)
  end
end
