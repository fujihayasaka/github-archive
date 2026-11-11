# typed: true
# frozen_string_literal: true

class MarketplaceAgreementSignaturesController < ApplicationController

  before_action :marketplace_required
  before_action :login_required
  before_action :agreement_and_listing_required

  stylesheet_bundle :marketplace

  def create
    unless params[:accept].to_s == "1"
      flash[:error] = "You must accept the terms of the agreement."
      return redirect_to :back
    end

    return render_404 unless viewer_can_sign_agreement?

    unless this_marketplace_listing.sign_agreement(current_user, agreement: this_marketplace_agreement)
      flash[:error] = "Could not sign the GitHub #{this_marketplace_agreement.name}."
    end

    redirect_to :back
  end

  private

  def target_for_conditional_access
    return :no_target_for_conditional_access unless this_marketplace_agreement.integrator? # rubocop:todo GitHub/SpecifyTargetForConditionalAccess

    this_marketplace_listing.owner
  end

  memoize def this_marketplace_agreement
    Marketplace::Agreement.find_by(id: params[:marketplace_agreement_id])
  end

  memoize def this_marketplace_listing
    Marketplace::Listing.find_by(id: params[:marketplace_listing_id])
  end

  def agreement_and_listing_required
    render_404 unless this_marketplace_agreement && this_marketplace_listing
  end

  def viewer_can_sign_agreement?
    if this_marketplace_agreement.integrator?
      unless this_marketplace_listing.can_sign_integrator_agreement?(current_user, agreement: this_marketplace_agreement)
        return false
      end
    elsif this_marketplace_agreement.end_user?
      unless this_marketplace_listing.can_sign_end_user_agreement?(current_user, agreement: this_marketplace_agreement)
        return false
      end
    end
    true
  end
end
