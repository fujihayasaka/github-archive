# typed: true
# frozen_string_literal: true

class MarketplaceListingSecurityAndComplianceController < ApplicationController
  before_action :ensure_listing_admin
  before_action :marketplace_required
  before_action :sudo_filter
  before_action :this_marketplace_listing_required

  layout "layouts/marketplace"
  stylesheet_bundle :marketplace

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Configurations,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::IssuesPullRequests,
    only: [:show]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:show],
    optional: true

  def show
    context_region_preset :marketplace

    return render_404 unless marketplace_listing.allowed_to_edit?(current_user)

    render "marketplace_listing_security_compliance/show", locals: { marketplace_listing: marketplace_listing }
  end

  def update
    context_region_preset :marketplace

    flash[:error] = nil
    flash[:notice] = nil
    marketplace_listing.assign_attributes(update_params)
    if marketplace_listing.errors.any?
      # User did not correctly specify other id type
      flash[:error] = marketplace_listing.errors.full_messages.to_sentence
    elsif marketplace_listing.save
      flash[:notice] = "Security and compliance information saved"
    else
      flash[:error] = marketplace_listing.errors.full_messages.to_sentence
    end

    render "marketplace_listing_security_compliance/show", locals: { marketplace_listing: marketplace_listing }
  end

  private

  def update_params
    new_params = permitted_params.slice(:trader_self_certification, :trader_address, :trader_id_type, :trader_id,
                                        :tos_url, :privacy_policy_url)
    new_params[:has_eu_compliance_attestation] = permitted_params[:has_eu_compliance_attestation] == "1"
    if permitted_params[:trader_self_certification] == "non_trader"
      new_params[:trader_address] = nil
      new_params[:trader_id_type] = nil
      new_params[:trader_id] = nil
    end
    if permitted_params[:trader_id_type] == "other"
      specified_id_type = permitted_params[:trader_id_type_other]
      if specified_id_type
        new_params[:trader_id_type] = specified_id_type
      else
        marketplace_listing.errors.add(:base, "Business id type is required")
      end
    end

    new_params
  end

  def permitted_params
    params.require(:marketplace_listing).permit(:trader_self_certification, :trader_address, :trader_id_type,
                                                :trader_id_type_other, :trader_id, :has_eu_compliance_attestation,
                                                :tos_url, :privacy_policy_url)
  end

  memoize def marketplace_listing
    Marketplace::Listing.find_by(slug: params[:listing_slug])
  end

  def ensure_listing_admin
    return if current_user&.biztools_user? || current_user&.site_admin?
    return if marketplace_listing && marketplace_listing.adminable_by?(current_user)
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
end
