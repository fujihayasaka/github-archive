# typed: strict
# frozen_string_literal: true

class Copilot::MaxSignupController < Copilot::Signup::BaseController
  include Copilot::VscodeRedirectConcern
  include Billing::ManualPaymentRedirect

  # Check this first as we don't want to leak any information about max prior to release.
  before_action :check_max_signup_enabled

  before_action :login_required, except: [:index]
  before_action :restrict_emu_access, except: [:index]
  before_action :check_for_active_copilot_max_subscription, only: [:new]
  before_action :check_max_net_new_signup_allowed, only: [:new, :create]
  before_action :check_trust_tier_for_max, only: [:new, :create]
  before_action :set_vscode_return_to, only: [:index, :new]
  before_action :add_vscode_form_action_csp, only: [:new]

  before_action only: [:new] do
    T.bind(self, Copilot::MaxSignupController)
    check_trade_compliance(target: current_user)
  end

  before_action only: [:create] do
    T.bind(self, Copilot::MaxSignupController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:index]
  before_action :enable_microsoft_analytics, only: [:index, :new]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:index, :new]

  javascript_bundle :billing, only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Configurations,
    only: [:index, :new]

  global_navigation_title "#{Copilot::INDIVIDUAL_MAX_PRODUCT_NAME} checkout", only: [:index, :new]

  sig { void }
  def new
    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_MAX_SIGNUP_PAGE_VIEW,
      copilot_user,
      utm_query_params: utm_query_params
    )
    GitHub.dogstats.increment("copilot.max_sku.signup_page_view")

    render "copilot/max/new", locals: {
      payment_duration: "monthly",
      premium_requests: signup_params[:premium_requests],
      return_to_path: preserve_tracking_params_path(copilot_max_signup_new_path, signup_params),
      subscribe_path: preserve_tracking_params_path(copilot_max_signup_create_path),
      tracking_params: tracking_params,
      copilot_user:,
      product_name:,
    }, formats: :html
  end

  sig { void }
  def index
    maybe_copilot_user = logged_in? ? copilot_user : nil

    if params[:cft] == "copilot_li.copilot_plans.cpm"
      # Redirect to Max signup if the user has simplified subscription flow enabled and entered with the right tracking param.
      redirect_to preserve_tracking_params_path(copilot_max_signup_new_path)
      return
    end

    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_MAX_PAGE_VIEW,
      maybe_copilot_user,
      utm_query_params: utm_query_params
    )
    GitHub.dogstats.increment("copilot.max_sku.page_view")

    render "copilot/max/index", locals: {
      form_submit_path: preserve_tracking_params_path(copilot_max_signup_new_path),
      tracking_params: tracking_params,
      copilot_user: maybe_copilot_user,
      product_name:,
    }, formats: :html
  end

  sig { void }
  def create
    return_to_path = signup_params[:return_to_path] || copilot_max_signup_new_path
    # There are no trials for Max
    is_trial_signup = false

    unless required_signup_params?
      flash[:error] = "Missing required parameters"
      return redirect_to preserve_tracking_params_path(return_to_path)
    end

    duration = :month

    url_options = { host: GitHub.admin_host_name, protocol: "https" }
    staff_url = stafftools_user_copilot_settings_url(current_user, **url_options)

    blocked = copilot_user.block_if_sharing_payment_method_with_other_blocked_users!

    if blocked
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup:,
        duration: duration.to_s,
        signed_up: false,
      )

      flash[:error] = "Unable to sign up for Copilot"
      return redirect_to preserve_tracking_params_path(copilot_features_path)
    end

    if copilot_user.shares_payment_method_with_blocked_user?
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup:,
        duration: duration.to_s,
        signed_up: true,
      )
    end
    result = copilot_user.subscribe_max(duration)

    if !result.ok?
      # If this is a re-POST from the manual payments page and we can confirm the payment was actually
      # collected, send them back to the upgrade page to activate again (the upgrade just hasn't caught
      # up yet) rather than looping them to the payment page. If we can't confirm payment went through,
      # fall through so they're redirected back to complete it instead of being reassured prematurely.
      if manual_payment_finalization? && result.error.is_a?(Billing::ManualPaymentRequiredError) &&
          manual_payment_collected?(target: current_user, invoice_id: result.error.invoice_id)
        flash[:error] = Billing::ManualPaymentRedirect::FINALIZATION_RETRY_MESSAGE
        redirect_to preserve_tracking_params_path(return_to_path)
        return
      end

      # An advance payment may have been declined because the customer must pay manually (India RBI).
      # If so, send them to the manual payments page to complete payment, which finalizes the upgrade.
      pending_upgrade = Copilot::Billing::PendingManualPaymentUpgrade.build(user: current_user, product_key: Copilot::INDIVIDUAL_MAX_PRODUCT_KEY)
      return if redirect_to_manual_payment_if_required(result.error, target: current_user, pending_upgrade: pending_upgrade)

      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(return_to_path)
      return
    end

    # A listener for this event will implictly refresh the user's Public cache
    # and emit a copilot license change event, see config/instrumentation/hydro/subscriptions/copilot_for_individuals.rb#L253
    # Because the license change event is emitted twice, we could theoretically get into
    # a situation in which the user:
    # * signs up for Max
    # * has their quote reset to 5k
    # * Use a few PRUs
    # * Has the quota reset again because of the second event.
    # This feels edge casey and acceptable enough for now.
    reloaded_copilot_user = Copilot::User.new(current_user)
    Copilot::Instrumenter.instrument_signup_subscription_created(
      reloaded_copilot_user,
      duration.to_s,
      0,
      utm_query_params:
    )

    Copilot::Instrumenter.instrument_max_subscription_created(
      reloaded_copilot_user,
      billing_frequency: duration.to_s,
    )

    send_marketing_email_consent if has_marketing_email_consent?

    return if redirect_to_vscode_if_needed

    success_path = signup_params[:success_path] || copilot_immersive_path
    redirect_to preserve_tracking_params_path(success_path)
  end

  sig { void }
  def update
    head :ok
  end

  sig { void }
  def downgrade # rubocop:todo GitHub/UseRestfulActions
    unless required_signup_params?
      flash[:error] = "Missing required parameters"
      redirect_to preserve_tracking_params_path(referrer)
      return
    end

    duration = :month

    if signup_params[:product_name] == Copilot.individual_pro_plus_product_name
      # Copilot::User#subscribe_pro_plus is used to downgrade from Max to Pro+
      result = copilot_user.subscribe_pro_plus(duration)
    elsif signup_params[:product_name] == Copilot.individual_pro_product_name
      # Copilot::User#subscribe_pro is used to downgrade from Max to Pro
      result = copilot_user.subscribe(duration)
    else
      flash[:error] = "Invalid product to downgrade to"
      redirect_to preserve_tracking_params_path(referrer)
      return
    end

    if !result.ok?
      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(referrer)
      return
    end

    Copilot::Instrumenter.instrument_max_subscription_downgraded(
      copilot_user,
      billing_frequency: duration.to_s
    )

    # Create or update the Copilot settings cache from new Copilot::User instance
    Copilot::User.new(current_user).create_copilot_settings_cache(Copilot::PolicyCacheVersion.current_version, reason: "downgrade_max")
    Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.for(current_user))

    redirect_to preserve_tracking_params_path(referrer)
  end

  private

  sig { void }
  def check_for_active_copilot_max_subscription
    redirect_to copilot_immersive_path if copilot_user.has_max_access?
  end

  sig { void }
  def check_max_net_new_signup_allowed
    return if copilot_user.copilot_max_new_signup_enabled?

    flash[:error] = "Copilot Max is only available as an upgrade from an existing paid plan."
    redirect_to preserve_tracking_params_path(copilot_features_path)
  end

  sig { void }
  def check_max_signup_enabled
    render_404 unless FeatureFlag.vexi.enabled?(:copilot_max_sku_signup, current_user, default: false)
  end

  sig { void }
  def check_trust_tier_for_max
    unless copilot_user.meets_trust_tier_requirements_for_max?
      flash[:error] = "Copilot Max isn't available for your account yet. Access is currently limited while we expand our rollout."
      redirect_to preserve_tracking_params_path(copilot_features_path)
    end
  end

  sig { returns(String) }
  def product_name
    Copilot::INDIVIDUAL_MAX_PRODUCT_NAME
  end

  sig { returns(Integer) }
  def pru_quota
    T.must(Copilot::Quotas.premium_interactions_monthly_quotas["Max"])
  end

  sig { returns(T::Boolean) }
  def required_signup_params?
    true
  end

  sig { returns(ActionController::Parameters) }
  memoize def user_contact_info_params
    params.require(:user_contact_info).permit(
      :first_name,
      :last_name,
      :email,
      :country,
      :marketing_consent,
    )
  end

  sig { returns(String) }
  def microsoft_analytics_order_id
    timestamp = Time.now.strftime("%m%d") # month, day
    Digest::SHA256.hexdigest("#{timestamp}-#{product_name}-#{current_user.display_login}")
  end

  sig { returns(T::Boolean) }
  def has_marketing_email_consent?
    return false unless user_contact_info_params.present?
    return false unless user_contact_info_params[:marketing_consent].present?

    user_contact_info_params[:marketing_consent] == "1"
  end

  sig { void }
  def send_marketing_email_consent
    MarketingConsentSubmissionJob.perform_later(
      email: user_contact_info_params[:email],
      country: user_contact_info_params[:country],
      source: "copilot-max-signup"
    )
  end
end
