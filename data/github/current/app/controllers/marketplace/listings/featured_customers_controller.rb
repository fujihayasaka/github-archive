# typed: true
# frozen_string_literal: true

class Marketplace::Listings::FeaturedCustomersController < ApplicationController

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  before_action :marketplace_required
  before_action :login_required
  before_action :this_marketplace_listing_required
  before_action :this_marketplace_listing_edit_required
  before_action :this_marketplace_listing_verified_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:index]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index],
    optional: true

  def index
    if GitHub.flipper[:deprecate_featured_customers].enabled?(this_marketplace_listing.integratable)
      render_404
    else
      render "marketplace_listing_featured_customers/index", locals: {
        marketplace_listing: this_marketplace_listing,
        featured_organizations: this_marketplace_listing.featured_organizations_non_spammy
      }
    end
  end

  def update
    existing_org_logins = Organization.where(id: this_marketplace_listing.featured_organizations.pluck(:organization_id)).pluck(:login)
    new_org_logins = params[:marketplace_listing][:featured_organization_login].compact - existing_org_logins

    organizations = Organization.where(login: new_org_logins)
    added_orgs = this_marketplace_listing.featured_organizations.create(organizations.map { |org| { organization: org } })

    if added_orgs.any? && this_marketplace_listing.publicly_listed?
      MarketplaceMailer.featured_customers_need_review(listing: this_marketplace_listing).deliver_later
    end

    redirect_to edit_featured_customers_marketplace_listing_path(this_marketplace_listing.slug)
  end

  def destroy
    customer = this_marketplace_listing.featured_organizations.find(params[:id])
    return render_404 unless customer

    customer.destroy
    flash[:notice] = "Customer removed successfully."

    redirect_to edit_featured_customers_marketplace_listing_path(customer.listing.slug)
  end

  private

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def this_marketplace_listing_required
    render_404 unless this_marketplace_listing
  end

  def this_marketplace_listing_edit_required
    render_404 unless this_marketplace_listing.allowed_to_edit?(current_user)
  end

  def this_marketplace_listing_verified_required
    render_404 unless this_marketplace_listing.verified?
  end

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_marketplace_listing # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
    this_marketplace_listing.owner
  end
end
