# typed: true
# frozen_string_literal: true

class Marketplace::Listings::VerifiedApprovalRequestsController < Marketplace::Listings::BaseController

  before_action :this_marketplace_listing_required
  before_action :this_marketplace_listing_admin_required

  def create
    if this_marketplace_listing.verified_approval_requestable_by?(current_user)
      this_marketplace_listing.request_verified_approval!(current_user)
      flash[:notice] = "Thank you for your submission. We will review your listing and get back to " +
                       "you shortly."
    else
      flash[:error] = "Marketplace listing cannot be submitted for review."
    end

    redirect_to :back
  end

  def initiate_financial_approval # rubocop:todo GitHub/UseRestfulActions
    if this_marketplace_listing.can_request_verified_approval?
      this_marketplace_listing.request_verified_approval!(current_user)
    else
      flash[:error] = "Cannot initiate financial onboarding"
    end

    redirect_to marketplace_listing_plan_path(params[:listing_slug], params[:id])
  end

end
