# typed: true
# frozen_string_literal: true

class Biztools::MarketplaceFeaturedCustomersController < BiztoolsController

  before_action :marketplace_required

  def update
    if org.update(featured_organization_params)
      flash[:notice] = success_flash_notice
      redirect_to biztools_edit_marketplace_listing_path(org.listing.slug)
    else
      flash[:error] = org.errors.messages.values.join(", ")
      redirect_to :back
    end
  end

  private

  memoize def org
    Marketplace::ListingFeaturedOrganization.find params[:id]
  end

  def featured_organization_params
    params.require(:featured_customers).permit(:approved)
  end

  def success_flash_notice
    "#{org.organization.name} has been #{org.approved? ? 'approved' : 'unapproved'}"
  end
end
