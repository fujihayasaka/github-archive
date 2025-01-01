# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::TrialsController < ::Businesses::BusinessController
  include BillingSettingsHelper
  include SecretScanning::Features::FeatureFlagHelper

  before_action :business_access_required
  before_action :ensure_billing_enabled
  before_action :trial_eligibility_required
  before_action :ensure_not_spammy_user
  before_action :ensure_trade_compliance

  sig { void }
  def create

    if this_business.has_active_advanced_security_subscription?
      flash[:error] = "This account is already subscribed to Advanced Security"
      return redirect_to_enterprise_licensing_or_return_to
    end

    create_volume_unbundled_ghas_trial = this_business.admins.any? && feature_flag_enabled?(this_business.admins.first, FeatureFlags::GHAS_VOLUME_UNBUNDLED_TRIALS)

    result = this_business.subscribe_to_advanced_security_trial(
      actor: current_user,
      billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
      volume_unbundled_trial: create_volume_unbundled_ghas_trial
    )
    if result.ok?
      if this_business.organization_for_advanced_security_trial(actor: current_user).nil?
        flash[:notice] = "Create an organization to use your new advanced security trial."
      else
        flash[:success] = "Subscribed to Advanced Security Trial"
      end
      analytics_event(
        category: "business_advanced_security_subscription",
        action: "subscribe_to_trial",
        label: "business_id:#{this_business.id}; dual_enterprise_trial:#{this_business.trial?}; trial_days:#{this_business.new_advanced_security_trial_days}"
      )
    else
      flash[:error] = result.error.message
    end

    redirect_to_enterprise_licensing_or_return_to
  end

  private

  sig { void }
  def trial_eligibility_required
    render_404 unless this_business.eligible_for_self_serve_advanced_security_trial?
  end

  sig { void }
  def redirect_to_enterprise_licensing_or_return_to
    if params[:return_to].present?
      safe_redirect_to params[:return_to], fallback: enterprise_licensing_path(this_business)
    else
      redirect_to enterprise_licensing_path(this_business)
    end
  end

  sig { void }
  def ensure_trade_compliance
    check_trade_compliance(
      target: this_business,
      sdn_redirect: true,
      redirect_url: settings_billing_tab_enterprise_url(tab: :payment_information)
    )
  end
end
