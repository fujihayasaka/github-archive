# typed: true
# frozen_string_literal: true

class Copilot::ProSignupController < Copilot::Signup::BaseController
  before_action :login_required, except: [:index]
  before_action :check_for_active_copilot_pro_or_pro_plus_subscription, only: [:new]

  before_action only: [:new] do
    T.bind(self, Copilot::ProSignupController)
    check_trade_compliance(target: current_user)
  end

  before_action only: [:create] do
    T.bind(self, Copilot::ProSignupController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  before_action :set_trial_signup, only: [:create]

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

  def index
    copilot_user_or_nil = logged_in? ? copilot_user : nil

    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_PRO_PAGE_VIEW,
      copilot_user_or_nil,
      utm_query_params: utm_query_params
    )

    context_region_title "Copilot Pro"

    render "copilot/pro/index", locals: {
      form_submit_path: preserve_tracking_params_path(copilot_pro_signup_new_path),
      payment_duration: signup_params[:payment_duration] || "monthly",
      tracking_params: tracking_params,
      copilot_user: copilot_user_or_nil,
    }, formats: :html
  end

  def new
    Copilot::Instrumenter.instrument_page_view(
      Copilot::Events::COPILOT_PRO_SIGNUP_PAGE_VIEW,
      copilot_user,
      utm_query_params: utm_query_params
    )

    context_region_title "Copilot Pro checkout"

    render "copilot/pro/new", locals: {
      payment_duration: signup_params[:payment_duration] || "monthly",
      premium_requests: signup_params[:premium_requests],
      return_to_path: preserve_tracking_params_path(copilot_pro_signup_new_path, signup_params),
      subscribe_path: preserve_tracking_params_path(copilot_pro_signup_create_path),
      tracking_params: tracking_params,
      copilot_user: copilot_user,
    }, formats: :html
  end

  sig { void }
  def update
    if feature_enabled_globally_or_for_current_user?(:copilot_pro_premium_requests)
      redirect_to preserve_tracking_params_path(copilot_pro_signup_new_path, signup_params.slice(:payment_duration, :premium_requests))
    else
      redirect_to preserve_tracking_params_path(copilot_pro_signup_new_path, signup_params.slice(:payment_duration))
    end
  end

  def create
    return_to_path = signup_params[:return_to_path] || copilot_pro_signup_new_path

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
        is_trial_signup: trial_signup?,
        duration: duration.to_s,
        signed_up: false,
      )

      flash[:error] = "Unable to sign up for Copilot"
      return redirect_to preserve_tracking_params_path(copilot_signup_path)
    end

    if copilot_user.shares_payment_method_with_blocked_user?
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: trial_signup?,
        duration: duration.to_s,
        signed_up: true,
      )
    end

    if trial_signup? && invalid_contact_email?
      flash[:error] = "Please enter a valid email address"
      return redirect_to preserve_tracking_params_path(return_to_path)
    end

    if feature_enabled_globally_or_for_current_user?(:copilot_pro_premium_requests)
      if signup_params[:premium_requests] == "enabled"
        copilot_user.overages_enabled!
      elsif signup_params[:premium_requests] == "disabled"
        copilot_user.overages_disabled!
      end
    end

    result = copilot_user.subscribe(duration)

    if result.ok?
      # Queue up an auth and capture check so we can find out whether the payment details are
      # valid before the trial ends
      if trial_signup? && current_user.feature_enabled?(:copilot_billing_auth_and_capture_users)
        is_trusted = TrustTiers::Tier.for_billable_owner(copilot_user).tier <= TrustTiers::Tier::TRUSTED
        copilot_user.perform_auth_and_capture!(skip_account_age_check: true, audit_log_reason: "trial_signup", delay: 1.minute) unless is_trusted
      end

      # this should be inside the subscribe
      Copilot::LimitedUser.find_by(user_id: copilot_user.id)&.destroy
      subscription = result.value { nil }

      Copilot::Instrumenter.instrument_signup_subscription_created(
        copilot_user,
        duration.to_s,
        subscription.free_trial_length.to_i,
        utm_query_params: utm_query_params
      )

      Copilot::Instrumenter.instrument_pro_subscription_created(
        copilot_user,
        billing_frequency: duration.to_s,
      )

      if signup_params[:success_path] == spark_dashboard_path
        Copilot::Instrumenter.instrument_subscription_created(
          Copilot::Events::COPILOT_SPARK_PRO_SUBSCRIPTION_CREATED,
          copilot_user: copilot_user,
          billing_frequency: duration.to_s,
        )
      end

      # Create or update the Copilot settings cache from new Copilot::User instance
      # https://github.com/github/heart-services/issues/5978
      Copilot::User.new(current_user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)

      if trial_signup?
        send_new_trial_signup_notifications
      elsif has_marketing_email_consent?
        send_marketing_email_consent
      end

      if copilot_user.is_technical_preview_user?
        tp_user = Copilot::TechnicalPreviewUser.find_by(user: copilot_user)
        tp_user.subscribe if tp_user.present?
      end

      success_path = signup_params[:success_path] || copilot_immersive_path
      redirect_to preserve_tracking_params_path(success_path)
    else
      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(copilot_signup_path)
    end
  end

  private

  sig { void }
  def check_for_active_copilot_pro_or_pro_plus_subscription
    return unless feature_enabled_globally_or_for_current_user?(:site_copilot_signup_redirect_active_subscription)
    redirect_to copilot_immersive_path if copilot_user.has_pro_plus_access? || copilot_user.has_pro_access?
  end

  sig { returns(T::Boolean) }
  def required_signup_params?
    has_payment_duration = %w(monthly yearly).include?(signup_params[:payment_duration])

    if feature_enabled_globally_or_for_current_user?(:copilot_pro_premium_requests)
      has_premium_requests = %w(disabled enabled).include?(signup_params[:premium_requests])

      has_payment_duration && has_premium_requests
    else
      has_payment_duration
    end
  end

  memoize def user_contact_info_params
    params.require(:user_contact_info).permit(
      :first_name,
      :last_name,
      :email,
      :country,
      :marketing_consent,
    )
  end

  def user_signup_contact_info_for_marketing
    cdl_program_name = GitHub.copilot_trial_campaign_id
    source = GitHub.copilot_trial_lead_source.presence || GitHub.copilot_trial_campaign_id
    sf_status = GitHub.copilot_trial_sf_status
    {
      first_name: user_contact_info_params[:first_name],
      last_name: user_contact_info_params[:last_name],
      email_address: user_contact_info_params[:email],
      country: user_contact_info_params[:country],
      marketingConsent: user_contact_info_params[:marketing_consent] ? "optInExplicit" : nil,
      cDLProgramName: cdl_program_name,
      source: source,
      sFDCLastCampaignStatus: sf_status,
    }.merge(
      utm_query_params.slice(:utm_campaign, :utm_medium, :utm_source)
    ).stringify_keys
  end

  sig { returns(T::Boolean) }
  def trial_signup?
    !!@trial_signup
  end

  # Memoizing trial signup in a before_action so that it is not affected by the user state changing
  sig { void }
  def set_trial_signup
    @trial_signup = T.let(copilot_user.eligible_for_trial?, T.nilable(T::Boolean))
  end

  def microsoft_analytics_order_id
    timestamp = Time.now.strftime("%m%d") # month, day
    Digest::SHA256.hexdigest("#{timestamp}-#{Copilot.individual_product_name}-#{current_user.display_login}")
  end

  def send_new_trial_signup_notifications
    MarketingFormsSubmissionJob.perform_later(form_name: "copilot-trial-new", raw_data: user_signup_contact_info_for_marketing)
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
      source: "copilot-pro-signup"
    )
  end

  def invalid_contact_email?
    return true unless user_contact_info_params[:email].present?
    !user_contact_info_params[:email].match?(UserEmail::MarketingDependency::EMAIL_REGEX)
  end
end
