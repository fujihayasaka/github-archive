# typed: true
# frozen_string_literal: true

class Marketplace::Listings::BaseController < ApplicationController
  before_action :marketplace_required
  before_action :login_required

  private

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

  def this_marketplace_listing_admin_required
    render_404 unless this_marketplace_listing.adminable_by?(current_user)
  end

end
