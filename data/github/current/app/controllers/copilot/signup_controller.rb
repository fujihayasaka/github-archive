# typed: true
# frozen_string_literal: true

class Copilot::SignupController < ApplicationController
  extend T::Sig
  include TradeControlsHelper
  before_action :login_required
  before_action :restrict_enterprise_access, except: [:choose_plan_type]
  before_action :restrict_multi_tenant_access
  before_action :check_user_type, only: [:new]
  before_action :require_free_user, only: [:free_signup]
  before_action :check_copilot_administrative_block, only: [:subscribe, :subscribe_free_user]

  before_action only: [:new, :signup_billing] do
    T.bind(self, Copilot::SignupController)
    check_trade_compliance(target: current_user)
  end

  before_action only: :subscribe do
    T.bind(self, Copilot::SignupController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  before_action :set_trial_signup, only: :subscribe

  before_action :add_csp_exceptions, only: [:settings]
  before_action :add_paypal_csp_exceptions, only: [:signup_billing]

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:new, :free_signup, :signup_billing, :settings, :success, :choose_plan_type]
  before_action :enable_microsoft_analytics, only: [:new, :free_signup, :signup_billing, :settings, :success, :choose_plan_type]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new, :free_signup, :signup_billing, :settings, :success, :choose_plan_type]
  layout "enterprise_funnel"

  stylesheet_bundle :copilot

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:free_signup]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:signup_billing]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:success]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Copilot,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    only: [:choose_plan_type]

  UTM_PARAMS = [:utm_source, :utm_medium, :utm_campaign, :utm_term, :utm_content].freeze
  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com", GitHub.urls.octocaptcha_host_name],
    media_src: [GitHub.asset_host_url],
    connect_src: [GitHub.asset_host_url]
  }

  def choose_plan_type # rubocop:todo GitHub/UseRestfulActions
    utm_params = request.query_parameters.symbolize_keys.slice(*UTM_PARAMS)
    default_plan = if %w(business enterprise individual).include?(params[:plan])
      params[:plan]
    else
      "enterprise"
    end

    render "copilot/signup_choose_plan_type", locals: {
      utm_params: utm_params,
      business_only: params[:business_only],
      default_plan: default_plan,
      enterprise: params[:enterprise],
    }, formats: :html
  end

  def new
    Copilot::Instrumenter.instrument_signup_page_view(copilot_user, utm_query_params: utm_query_params)

    signup_duration = signup_params && signup_params[:payment_duration] == "yearly" ? :year : :month

    render "copilot/signup", locals: {
      copilot_user: copilot_user,
      signup_duration: signup_duration,
      form_submit_path: preserved_query_params_path(copilot_signup_billing_path),
      tracking_params: tracking_query_params,
    }, formats: :html
  end

  def renew # rubocop:todo GitHub/UseRestfulActions
    Copilot::Instrumenter.instrument_signup_page_view(copilot_user, utm_query_params: utm_query_params)

    signup_duration = signup_params && signup_params[:payment_duration] == "yearly" ? :year : :month

    utm_params = request.query_parameters.symbolize_keys.slice(*UTM_PARAMS)

    render "copilot/signup", locals: {
      copilot_user: copilot_user,
      signup_duration: signup_duration,
      form_submit_path: preserved_query_params_path(copilot_signup_billing_path),
      utm_params: utm_params,
    }, formats: :html
  end

  def free_signup # rubocop:todo GitHub/UseRestfulActions
    Copilot::Instrumenter.instrument_signup_free_page_view(copilot_user, utm_query_params: utm_query_params)

    render "copilot/free_signup", locals: {
      copilot_user: copilot_user,
      form_submit_path: preserved_query_params_path(copilot_signup_subscribe_free_user_path)
    }, formats: :html
  end

  def signup_billing # rubocop:todo GitHub/UseRestfulActions
    if !signup_billing_valid
      flash[:error] = "Missing required parameters"
      redirect_to preserved_query_params_path(copilot_signup_path)
      return
    end
    show_billing
  end

  def settings # rubocop:todo GitHub/UseRestfulActions
    if !signup_params[:public_code_suggestions] || signup_params[:public_code_suggestions] == ""
      return render "copilot/signup_success", locals: {
        copilot_user: copilot_user,
        error: true,
        form_submit_path: preserved_query_params_path(copilot_signup_settings_path)
      }
    end

    old_settings = copilot_user.copilot_user_settings

    signup_params[:public_code_suggestions] == "allowed" ? copilot_user.allow_public_code_suggestions! : copilot_user.block_public_code_suggestions!
    signup_params[:telemetry] == "Allow" ? copilot_user.enable_telemetry! : copilot_user.disable_telemetry!

    new_settings = copilot_user.copilot_user_settings

    Copilot::Instrumenter.instrument_signup_settings_saved(
      copilot_user,
      old_settings: old_settings,
      new_settings: new_settings,
      utm_query_params: utm_query_params
    )

    render "copilot/get_started", locals: {
      microsoft_analytics_order_id: microsoft_analytics_order_id,
      copilot_subscription_period: copilot_subscription_period,
      new_signup: params[:new_signup]
    }
  end

  def success # rubocop:todo GitHub/UseRestfulActions
    render "copilot/signup_success", locals: { copilot_user: copilot_user, form_submit_path: preserved_query_params_path(copilot_signup_settings_path) }, formats: :html
  end

  def subscribe # rubocop:todo GitHub/UseRestfulActions
    if !signup_billing_valid
      flash[:error] = "Missing required parameters"
      redirect_to preserved_query_params_path(copilot_signup_path)
      return
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
      redirect_to preserved_query_params_path(copilot_signup_path)
      return
    end

    if copilot_user.shares_payment_method_with_blocked_user?
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: trial_signup?,
        duration: duration.to_s,
        signed_up: true,
      )
    end

    if marketing_trial? && !valid_contact_email?
      flash[:error] = "Please enter a valid email address"
      redirect_to preserved_query_params_path(copilot_signup_path)
      return
    end

    result = copilot_user.subscribe(duration)

    # Queue up an auth and capture check so we can find out whether the payment details are
    # valid before the trial ends
    if trial_signup? && current_user.feature_enabled?(:copilot_billing_auth_and_capture_users)
      is_trusted = TrustTiers::Tier.for_billable_owner(copilot_user).tier <= TrustTiers::Tier::TRUSTED
      copilot_user.perform_auth_and_capture!(skip_account_age_check: true, audit_log_reason: "trial_signup", delay: 1.minute) unless is_trusted
    end

    if result.ok?
      subscription = result.value { nil }

      Copilot::Instrumenter.instrument_signup_subscription_created(
        copilot_user,
        duration.to_s,
        subscription.free_trial_length.to_i, # trial length
        utm_query_params: utm_query_params
      )

      CopilotForIndividualsMailer.trial_welcome(current_user).deliver_later if trial_signup?

      send_marketing_notifications

      redirect_to preserved_query_params_path(copilot_signup_success_path)
    else
      flash[:error] = result.error.message
      redirect_to preserved_query_params_path(copilot_signup_path)
    end
  end

  def subscribe_free_user # rubocop:todo GitHub/UseRestfulActions
    result = copilot_user.subscribe_free_user
    if result.ok?
      Copilot::Instrumenter.instrument_signup_free_subscription_created(copilot_user, utm_query_params: utm_query_params)
      redirect_to preserved_query_params_path(copilot_signup_success_path)
    else
      flash[:error] = result.error.message
      redirect_to preserved_query_params_path(copilot_signup_path)
    end
  end

  def upgrade_trial # rubocop:todo GitHub/UseRestfulActions
    if copilot_user.has_trial_subscription?
      result = copilot_user.upgrade_trial
      flash[:error] = result.error.message unless result.ok?
    else
      flash[:error] = "No active trial"
    end

    redirect_to settings_user_billing_path
  end

  private

  def add_paypal_csp_exceptions
    paypal_csp_exceptions = {
      img_src: [GitHub.paypal_checkout_url],
      connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url]
    }
    SecureHeaders.append_content_security_policy_directives(request, paypal_csp_exceptions)
  end

  def show_billing
    Copilot::Instrumenter.instrument_signup_plan_chosen(
      copilot_user,
      signup_params[:payment_duration],
      utm_query_params: utm_query_params,
    )

    if copilot_user.eligible_for_trial?
      render "copilot/signup_billing", locals: {
        login: current_user.display_login,
        avatar: current_user.primary_avatar_url,
        payment_duration: signup_params[:payment_duration],
        current_user: current_user,
        return_to_path: preserved_query_params_path(copilot_signup_billing_path, signup_params),
        subscribe_path: preserved_query_params_path(copilot_signup_subscribe_path),
        copilot_user: copilot_user
      }, formats: :html
    else
      render "copilot/renew_signup_billing", locals: {
        login: current_user.display_login,
        avatar: current_user.primary_avatar_url,
        payment_duration: signup_params[:payment_duration],
        current_user: current_user,
        return_to_path: preserved_query_params_path(copilot_signup_billing_path, signup_params),
        subscribe_path: preserved_query_params_path(copilot_signup_subscribe_path),
        copilot_user: copilot_user
      }, formats: :html
    end
  end

  def signup_billing_valid
    signup_params[:payment_duration] == "monthly" || signup_params[:payment_duration] == "yearly"
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

  def signup_params
    params.permit(
      :agree, :action, :login, :authenticity_token, :payment_duration, :telemetry, :editor, :_method, :public_code_suggestions, :new_signup,
      *UTM_PARAMS,
      user_contact_info: [:first_name, :last_name, :email, :country, :marketing_consent]
    )
  end

  sig { returns(Copilot::User) }
  memoize def copilot_user
    T.must_because(current_copilot_user) { "#login_required ensures non-nil" }
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

  # Users can only really be in one of three states
  # 1. They have an active subscription or free access
  # 2. They're an enterprise user and have their access managed
  # 3. They can sign up for a subscription or free access
  def check_user_type
    # if they have already signed up or are an enterprise user
    # we want to redirect them to the copilot settings page
    redirect_to "/settings/copilot" and return if copilot_user.has_signed_up? || copilot_user.is_enterprise_managed?

    # if a user can sign up for free, send them to free signup
    redirect_to preserved_query_params_path(copilot_free_signup_path) and return if copilot_user.can_signup_for_free?
  end

  # Users can only navigate to free_signup if they are a free user
  def require_free_user
    return if copilot_user.can_signup_for_free?
    redirect_to preserved_query_params_path(copilot_signup_path)
  end

  def target_for_conditional_access
    logged_in? ? current_user : :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    logged_in? ? current_user : :no_resource_for_conditional_access # rubocop:disable GitHub/SpecifyResourceForConditionalAccess
  end

  def preserved_query_params_path(to_path, additional_params = {})
    params = tracking_query_params.merge(additional_params)
    return to_path if params.empty?

    uri = URI::HTTP.build(path: to_path, query: params.to_query)
    # only return the absolute path and query, don't include blank hostname and protocol
    "#{uri.path}?#{uri.query}"
  end

  def restrict_enterprise_access
    # if a user is on an enterprise subscription we want to redirect them to the copilot settings page
    if copilot_user.orgs_using_copilot_for_business.any?
      redirect_to "/settings/copilot"
    end
  end

  def check_copilot_administrative_block
    if copilot_user.administrative_blocked?
      flash[:error] = "Your account is unable to sign up for Copilot. Please contact Support"
      redirect_to preserved_query_params_path(copilot_signup_path)
    end
  end

  def restrict_multi_tenant_access
    # if a user is on a multi-tenant instance we want to redirect them to the copilot settings page
    redirect_to "/settings/copilot" if GitHub.multi_tenant_enterprise?
  end

  memoize def tracking_query_params
    tracking_params = request.query_parameters.slice(:new_signup, *UTM_PARAMS).symbolize_keys

    tracking_params.merge!(utm_source: params[:editor], utm_medium: "editor") if override_utm_for_editor?

    tracking_params
  end

  def override_utm_for_editor?
    return false if params.key?(:utm_source) || params.key?(:utm_medium)

    request.query_parameters[:editor].present?
  end

  def utm_query_params
    tracking_query_params.slice(*UTM_PARAMS)
  end

  def microsoft_analytics_order_id
    timestamp = Time.now.strftime("%m%d") # month, day
    Digest::SHA256.hexdigest("#{timestamp}-#{Copilot.individual_product_name}-#{current_user.display_login}")
  end

  # Returns the subscription type of the user, either "month", "year", or "free"
  def copilot_subscription_period
    if copilot_user.copilot_active_subscription_item.present?
      copilot_user.copilot_active_subscription_item&.interval.to_s
    elsif copilot_user.free_user.present? && copilot_user.free_user&.subscribed
      "free"
    end
  end

  def send_marketing_notifications
    if marketing_trial?
      MarketingFormsSubmissionJob.perform_later(form_name: "copilot-trial-new", raw_data: user_signup_contact_info_for_marketing)
    elsif copilot_user.is_technical_preview_user?
      uri = "https://s88570519.t.eloqua.com/e/f2?elqFormName=UntitledForm-1654030645645&elqSiteID=88570519"
      eloqua_args = { uri: uri, email: current_user.email }
      Copilot::SendEmailToEloquaJob.perform_later(eloqua_args)

      tp_user = Copilot::TechnicalPreviewUser.find_by(user: copilot_user)
      tp_user.subscribe if tp_user.present?
    end
  end

  def marketing_trial?
    current_user.feature_enabled?(:marketing_forms_api_integration_copilot_trial) && trial_signup?
  end

  def valid_contact_email?
    return false unless user_contact_info_params[:email].present?
    user_contact_info_params[:email].match?(UserEmail::MarketingDependency::EMAIL_REGEX)
  end
end
