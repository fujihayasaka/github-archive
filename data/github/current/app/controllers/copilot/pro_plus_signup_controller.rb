# typed: strict
# frozen_string_literal: true

class Copilot::ProPlusSignupController < Copilot::Signup::BaseController
  before_action :login_required, except: [:index]
  before_action :check_for_active_copilot_pro_plus_subscription, only: [:new]

  before_action only: [:new] do
    T.bind(self, Copilot::ProPlusSignupController)
    check_trade_compliance(target: current_user)
  end

  before_action only: [:create] do
    T.bind(self, Copilot::ProPlusSignupController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  before_action :add_paypal_csp_exceptions, only: [:new]

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

  sig { void }
  def index
    copilot_user_or_nil = logged_in? ? copilot_user : nil

    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_PRO_PLUS_PAGE_VIEW,
      copilot_user_or_nil,
      utm_query_params: utm_query_params
    )

    context_region_title "Copilot Pro+"

    render "copilot/pro_plus/index", locals: {
      form_submit_path: preserve_tracking_params_path(copilot_pro_plus_signup_new_path),
      payment_duration: signup_params[:payment_duration] || "monthly",
      tracking_params: tracking_params,
      copilot_user: copilot_user_or_nil,
    }, formats: :html
  end

  sig { void }
  def new
    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_PRO_PLUS_SIGNUP_PAGE_VIEW,
      copilot_user,
      utm_query_params: utm_query_params
    )

    context_region_title "Copilot Pro+ checkout"

    render "copilot/pro_plus/new", locals: {
      payment_duration: signup_params[:payment_duration] || "monthly",
      premium_requests: signup_params[:premium_requests],
      return_to_path: preserve_tracking_params_path(copilot_pro_plus_signup_new_path, signup_params),
      subscribe_path: preserve_tracking_params_path(copilot_pro_plus_signup_create_path),
      tracking_params: tracking_params,
      copilot_user: copilot_user,
    }, formats: :html
  end

  sig { void }
  def update
    redirect_to preserve_tracking_params_path(copilot_pro_plus_signup_new_path, signup_params.slice(:payment_duration, :premium_requests))
  end

  sig { void }
  def create
    return_to_path = signup_params[:return_to_path] || copilot_signup_path

    unless required_signup_params?
      flash[:error] = "Missing required parameters"
      return redirect_to preserve_tracking_params_path(return_to_path)
    end

    duration = signup_params[:payment_duration] == "monthly" ? :month : :year

    url_options = { host: GitHub.admin_host_name, protocol: "https" }
    staff_url = stafftools_user_copilot_settings_url(current_user, **url_options)

    blocked = copilot_user.block_if_sharing_payment_method_with_other_blocked_users!

    if blocked
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: false, # Pro+ doesn't offer trials
        duration: duration.to_s,
        signed_up: false,
      )
      flash[:error] = "Unable to sign up for Copilot"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
      return
    end

    if copilot_user.shares_payment_method_with_blocked_user?
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: false,
        duration: duration.to_s,
        signed_up: true,
      )
    end

    if feature_enabled_globally_or_for_current_user?(:copilot_pro_plus_premium_requests)
      if signup_params[:premium_requests] == "enabled"
        copilot_user.overages_enabled!
      elsif signup_params[:premium_requests] == "disabled"
        copilot_user.overages_disabled!
      end
    end

    result = copilot_user.subscribe_pro_plus(duration)

    if !result.ok?
      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(return_to_path)
      return
    end

    Copilot::Instrumenter.instrument_signup_subscription_created(
      copilot_user,
      duration.to_s,
      0, # today there is no trial for Pro+
      utm_query_params: utm_query_params
    )

    Copilot::Instrumenter.instrument_pro_plus_subscription_created(
      copilot_user,
      billing_frequency: duration.to_s
    )

    if signup_params[:success_path] == spark_dashboard_path
      Copilot::Instrumenter.instrument_subscription_created(
        Copilot::Events::COPILOT_SPARK_PRO_PLUS_SUBSCRIPTION_CREATED,
        copilot_user: copilot_user,
        billing_frequency: duration.to_s,
      )
    end

    send_marketing_email_consent if has_marketing_email_consent?

    # If the user has limited access (free tier), remove their free access record
    Copilot::LimitedUser.find_by(user_id: copilot_user.id)&.destroy
    if copilot_user.feature_enabled?(:copilot_free_remove_on_pro_plus_signup)
      Copilot::FreeUser.find_for_copilot_user(copilot_user)&.cancel!
    end

    # Create or update the Copilot settings cache from new Copilot::User instance
    # https://github.com/github/heart-services/issues/5978
    Copilot::User.new(current_user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

    success_path = signup_params[:success_path] || copilot_immersive_path
    redirect_to preserve_tracking_params_path(success_path)
  end

  sig { void }
  def downgrade # rubocop:todo GitHub/UseRestfulActions
    unless required_signup_params?
      flash[:error] = "Missing required parameters"
      redirect_to preserve_tracking_params_path(copilot_settings_path)
      return
    end

    duration = signup_params[:payment_duration] == "monthly" ? :month : :year
    # Copilot::User#subscribe is used to downgrade from Pro+ to Pro
    result = copilot_user.subscribe(duration)

    if !result.ok?
      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(copilot_settings_path)
      return
    end

    Copilot::Instrumenter.instrument_pro_plus_subscription_downgraded(
      copilot_user,
      billing_frequency: duration.to_s
    )

    # Create or update the Copilot settings cache from new Copilot::User instance
    # https://github.com/github/heart-services/issues/5978
    Copilot::User.new(current_user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
    flash[:notice] = "Your pending plan change has been successfully reverted."
    redirect_to preserve_tracking_params_path(copilot_settings_path)
  end

  private

  sig { void }
  def check_for_active_copilot_pro_plus_subscription
    return unless feature_enabled_globally_or_for_current_user?(:site_copilot_signup_redirect_active_subscription)
    redirect_to copilot_immersive_path if copilot_user.has_pro_plus_access?
  end

  sig { returns(T::Boolean) }
  def required_signup_params?
    has_payment_duration = %w(monthly yearly).include?(signup_params[:payment_duration])

    if feature_enabled_globally_or_for_current_user?(:copilot_pro_plus_premium_requests)
      has_premium_requests = %w(disabled enabled).include?(signup_params[:premium_requests])

      has_payment_duration && has_premium_requests
    else
      has_payment_duration
    end
  end

  sig { returns(T::Hash[Symbol, String]) }
  def user_contact_info_params
    signup_params.slice(:user_contact_info)
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
      email: T.must(user_contact_info_params[:email]),
      country: T.must(user_contact_info_params[:country]),
      source: "copilot-pro-plus-signup"
    )
  end
end
