# typed: true
# frozen_string_literal: true

# Implements the API that Alambic uses for serving or accepting marketplace listing
# screenshot uploads through the Alambic storage cluster. Used in local development.
#
# https://github.com/github/alambic/tree/master/docs/assets
class Api::Internal::StorageMarketplaceListingScreenshots < Api::Internal::StorageUploadable
  require_api_semantic_version "smasher"

  def self.enforce_private_mode?
    false
  end

  get "/internal/storage/marketplace-listing-screenshots/:id/files/:guid", operation_id: :internal do
    @route_owner = "@github/marketplace-eng"
    listing = ActiveRecord::Base.connected_to(role: :reading) { Marketplace::Listing.find(params[:id]) }
    control_access :read_marketplace_listing, marketplace_listing: listing, allow_integrations: false, allow_user_via_granular_actor: false

    screenshot = listing.screenshots.includes(:storage_blob, :listing).find_by_guid(params[:guid])
    deliver :internal_storage_hash, screenshot, env: request.env
  end

  post "/internal/storage/marketplace-listing-screenshots/:id/files", operation_id: :internal do
    @route_owner = "@github/marketplace-eng"
    listing = ActiveRecord::Base.connected_to(role: :reading) { Marketplace::Listing.find(params[:id]) }
    control_access :write_marketplace_listing, marketplace_listing: listing, allow_integrations: false, allow_user_via_granular_actor: false
    validate_uploadable Marketplace::ListingScreenshot,
      meta: { marketplace_listing_id: params[:id] }
  end

  post "/internal/storage/marketplace-listing-screenshots/:id/files/verify", operation_id: :internal do
    @route_owner = "@github/marketplace-eng"
    listing = ActiveRecord::Base.connected_to(role: :reading) { Marketplace::Listing.find(params[:id]) }
    control_access :write_marketplace_listing, marketplace_listing: listing, allow_integrations: false, allow_user_via_granular_actor: false
    create_uploadable Marketplace::ListingScreenshot,
      meta: { marketplace_listing_id: params[:id] }
  end

  def verify_user(meta)
    T.unsafe(Marketplace::ListingScreenshot).storage_verify_token(@asset_token, meta)
  end
end
