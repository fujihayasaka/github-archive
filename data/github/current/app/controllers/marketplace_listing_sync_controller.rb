# typed: true
# frozen_string_literal: true

class MarketplaceListingSyncController < ApplicationController

  before_action :ensure_listing_admin
  before_action :marketplace_required
  before_action :sudo_filter
  before_action :this_marketplace_listing_required
  before_action :feature_enabled
  before_action :listing_is_published

  depends_on_clusters ApplicationRecord::Mysql1,
  ApplicationRecord::Collab,
  ApplicationRecord::Mysql2,
  ApplicationRecord::IamAbilities,
  ApplicationRecord::Mysql5,
  ApplicationRecord::NotificationsEntries,
  ApplicationRecord::Billing,
  ApplicationRecord::Copilot,
  only: [:show]

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  def show
    return render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)

    render "marketplace_listing_sync/show", locals: {
      listing_slug: this_marketplace_listing.slug,
      marketplace_listing: this_marketplace_listing
    }
  end

  def update
    app = this_marketplace_listing.integratable
    msg = ""

    if params[:proxima_availability] == "1"
      app.proxima_availability = :available
      msg = "The marketplace listing has been opted in to sync in all regions."
    elsif app.feature_enabled?(:sync_deletions_to_proxima_apps)
      app.proxima_availability = :unavailable
      msg = "The marketplace listing has been opted out of syncing in all regions."
    end

    flash[:notice] = msg if app.save

    render "marketplace_listing_sync/show", locals: {
      listing_slug: this_marketplace_listing.slug,
      marketplace_listing: this_marketplace_listing
    }
  end

  private

  def ensure_listing_admin
    return if current_user&.biztools_user? || current_user&.site_admin?
    return if this_marketplace_listing && this_marketplace_listing.adminable_by?(current_user)
    render_404
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_marketplace_listing # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_marketplace_listing.owner
  end

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing
  end

  def feature_enabled
    render_404 unless GitHub::flipper[:third_party_sync_integrator_opt_in].enabled?(this_marketplace_listing.integratable)
  end

  def listing_is_published
    if current_user.feature_enabled?(:relax_sync_listing_requirement)
      render_404 unless this_marketplace_listing.publicly_listed?
    else
      render_404 unless this_marketplace_listing.publicly_listed? || this_marketplace_listing.verified?
    end
  end
end
