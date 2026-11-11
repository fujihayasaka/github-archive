# typed: true
# frozen_string_literal: true

# Shared helper methods for GHAS upsell banner and usage summary cards.
# Used by both the enterprise security_analysis_controller and org security_products_controller.
#
# Controllers including this concern must implement:
# - target_business: Returns the Business to check for upsell eligibility
#
# Controllers can optionally override:
# - organization_to_onboard: Returns the org to onboard after starting a trial
#
module SecurityProductsUpsellHelper
  extend T::Helpers
  extend ActiveSupport::Concern
  include GitHub::Memoizer

  requires_ancestor { ApplicationController }

  # Notice keys for banner dismissal - must match frontend constants in banner-helper.ts
  SELF_SERVE_GHAS_UPSELL_BANNER_NOTICE = "self_serve_ghas_upsell_banner_in_configs"
  VOLUME_GHAS_UPSELL_BANNER_NOTICE = "volume_ghas_upsell_banner_in_configs"

  # Controllers including this concern must implement this method.
  sig { returns(T.nilable(Business)) }
  def target_business
    raise NotImplementedError, "Including controller must implement #target_business"
  end

  # Check if the current user can see upsell content.
  # Only enterprise owners should see upsell banners and CTAs.
  def can_see_upsell?
    return false if current_user.nil?

    target_business&.owner?(T.must(current_user)) || false
  end

  # Helper to check if the business is eligible for a GHAS self-serve trial.
  memoize def eligible_for_trial?
    target_business&.eligible_for_self_serve_advanced_security_trial? || false
  end

  # Determines what type of upsell to show.
  # Returns:
  # - 'trial' for trial-eligible customers
  # - 'volume_contact_sales' for sales-managed (invoiced) customers without GHAS
  # - nil if no upsell should be shown or feature flag is disabled
  def upsell_type
    return nil unless usage_cards_feature_enabled?
    return nil unless can_see_upsell?

    return "trial" if eligible_for_trial?

    # Metered customers can self-enable GHAS, no need to contact sales
    return nil if target_business&.advanced_security_products_metered?

    # Sales-managed (invoiced) customers who haven't purchased GHAS should contact sales
    return "volume_contact_sales" if target_business&.sales_managed? && !target_business&.advanced_security_purchased?

    nil
  end

  # Helper to check if the upsell banner should be shown (not dismissed).
  # Uses enterprise-level dismissal so dismissing at enterprise level also hides on org pages.
  def show_upsell_banner?
    return false unless usage_cards_feature_enabled?
    return false unless can_see_upsell?
    return false if current_user.nil?
    return false if upsell_type.nil?

    notice_key = upsell_type == "trial" ? SELF_SERVE_GHAS_UPSELL_BANNER_NOTICE : VOLUME_GHAS_UPSELL_BANNER_NOTICE
    notice_dismissal = Growth::NoticeDismissal.new(T.must(current_user))
    !notice_dismissal.dismissed_business_notice?(
      notice_key,
      business_id: T.must(target_business).id,
      per_user: true
    )
  end

  # Helper to build self-serve trial info payload for the frontend.
  # Returns nil if the business is not eligible for a trial or feature flag is disabled.
  def self_serve_trial_info
    return nil unless usage_cards_feature_enabled?
    return nil unless can_see_upsell?
    return nil unless eligible_for_trial?

    {
      organizationToOnboard: organization_to_onboard&.to_param,
      showNoOrgsWarning: target_business&.filtered_organizations(viewer: current_user).empty?,
      # trialDays and trialExpired are required by the SelfServeTrialInfo interface
      # but not used by our TrialUpsellBanner component. We hardcode these values
      # since we only show the banner when eligible (not expired).
      trialDays: 30,
      trialExpired: false,
    }
  end

  # Returns the organization to onboard after starting a trial.
  # Override in controllers to provide a specific org (e.g., current org on org pages).
  def organization_to_onboard
    target_business&.organization_for_advanced_security_trial(actor: current_user)
  end

  # Helper to check if the usage cards feature flag is enabled.
  # Checks both business and user to allow staff testing.
  def usage_cards_feature_enabled?
    biz = target_business
    (biz && FeatureFlag.vexi.enabled?(:ghas_config_usage_cards, biz, default: false)) ||
      FeatureFlag.vexi.enabled?(:ghas_config_usage_cards, current_user, default: false)
  end
end
