# typed: true
# frozen_string_literal: true

class Marketplace::Listings::UnverifiedApprovalRequestsController < Marketplace::Listings::BaseController

  before_action :this_marketplace_listing_required
  before_action :this_marketplace_listing_admin_required

  def create
    if this_marketplace_listing.unverified_approval_requestable_by?(current_user)
      this_marketplace_listing.request_unverified_approval!(current_user)

      flash[:notice] = "Thank you for your submission. We will review your listing and get back to " +
                       "you shortly."
    else
      flash[:error] = "Marketplace listing cannot be submitted for review."
    end

    redirect_to :back
  end

end
