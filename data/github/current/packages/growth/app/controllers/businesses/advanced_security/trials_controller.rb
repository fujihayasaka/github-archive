# typed: strict
# frozen_string_literal: true

class Businesses::AdvancedSecurity::TrialsController < ::Businesses::BusinessController
  include BillingSettingsHelper
  include SecretScanning::Features::FeatureFlagHelper
  include VerifiedFetchDependency

  before_action :business_access_required
  before_action :ensure_billing_enabled
  before_action :trial_eligibility_required
  before_action :ensure_not_spammy_user
  before_action :ensure_trade_compliance

  allow_verified_fetch only: [:create]

  sig { void }
  def create
    if this_business.has_active_advanced_security_subscription?
      return handle_error("This account is already subscribed to Advanced Security")
    end

    # all self serve trials except digital front door are bundled, always
    # When the unbundled GHAS standalone trials feature flag is enabled for
    # this business, mark the trial as a volume-unbundled GHAS standalone
    # trial and set the trial_source so downstream licensing logic can
    # distinguish this flow.
    trial_opts = {}
    if this_business.feature_flag_enabled?(:unbundled_ghas_standalone_trials, default: false)
      trial_opts[:volume_unbundled_trial] = true
      trial_opts[:trial_source] = :ghas_stand_alone
    end

    result = this_business.subscribe_to_advanced_security_trial(
      actor: current_user,
      billing_cycle: Billing::Public::SubscriptionItems::BillingCycle::Month,
      **trial_opts,
    )
    if result.ok?
      if this_business.organization_for_advanced_security_trial(actor: current_user).nil?
        notice_message = "Create an organization to use your new advanced security trial."
      else
        success_message = "Subscribed to Advanced Security Trial"
      end
      analytics_event(
        category: "business_advanced_security_subscription",
        action: "subscribe_to_trial",
        label: "business_id:#{this_business.id}; dual_enterprise_trial:#{this_business.trial?}; trial_days:#{this_business.new_advanced_security_trial_days}"
      )
    else
      return handle_error(result.error.message)
    end

    handle_success(success_message, notice_message)
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

  sig { params(error_message: String).void }
  def handle_error(error_message)
    respond_to do |format|
      format.html do
        flash[:error] = error_message
        return redirect_to_enterprise_licensing_or_return_to
      end
      format.json { render json: { error: error_message }, status: :unprocessable_entity }
    end
  end

  sig { params(success_message: T.nilable(String), notice_message: T.nilable(String)).void }
  def handle_success(success_message = nil, notice_message = nil)
    respond_to do |format|
      format.html do
        flash[:notice] = notice_message if notice_message.present?
        flash[:success] = success_message if success_message.present?
        return redirect_to_enterprise_licensing_or_return_to
      end
      format.json { render json: {} }
    end
  end
end
