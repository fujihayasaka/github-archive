# typed: true
# frozen_string_literal: true

require "uri"
class Copilot::SignupController < ApplicationController
  include TradeControlsHelper

  before_action :login_required
  before_action :restrict_enterprise_access, except: [:choose_plan_type]
  before_action :restrict_multi_tenant_access
  before_action :check_user_type, only: [:new]
  before_action :require_free_user, only: [:free_signup]
  before_action :check_copilot_administrative_block, only: [:subscribe, :subscribe_free_user, :subscribe_limited_user]

  before_action only: [:new] do
    T.bind(self, Copilot::SignupController)
    check_trade_compliance(target: current_user)
  end

  before_action only: [:subscribe, :subscribe_limited_user] do
    T.bind(self, Copilot::SignupController)
    check_trade_compliance(target: current_user, feature_type: :copilot, sdn_redirect: true)
  end

  before_action :set_trial_signup, only: :subscribe
  before_action :add_csp_exceptions, only: [:settings]

  include Site::PreserveTrackingParamsDependency
  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:new, :free_signup, :choose_plan_type]
  before_action :enable_microsoft_analytics, only: [:new, :free_signup, :settings, :success, :choose_plan_type]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new, :free_signup, :settings, :success, :choose_plan_type]

  layout "enterprise_funnel"

  stylesheet_bundle :copilot

  javascript_bundle :copilot

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
    ApplicationRecord::Configurations,
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
  PERMITTED_SIGNUP_PARAMS = [:agree, :action, :login, :authenticity_token, :payment_duration, :telemetry, :editor, :_method,
    :public_code_suggestions, :new_signup, :cft, :copilot_policy_bing, :g_chat, :a_chat, :return_to,
    :dashboard_entry_point, :a_f, :o_ff, :o_f, :overages, :g_tf, :o_fm, :ofct, :o_t, :ofo, :al, :afos, :gtff,
    :aofo, :obmb, :obmw, :grok_code, :editor_preview_features, :dotcom_chat, :cli, :desktop, :chat, :mobile_chat,
    :automatic_code_review, :swe_agent, :mcp, :code_review].freeze

  CSP_EXCEPTIONS = {
    frame_src: ["https://www.youtube.com", GitHub.urls.octocaptcha_host_name],
    media_src: [GitHub.asset_host_url],
    connect_src: [GitHub.asset_host_url]
  }

  def choose_plan_type # rubocop:todo GitHub/UseRestfulActions
    utm_params = request.query_parameters.symbolize_keys.slice(*UTM_PARAMS)

    if params[:business_only]
      redirect_to preserve_tracking_params_path(copilot_plan_purchase_path(enterprise: params[:enterprise])) and return
    end

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
    check_copilot_administrative_block
    if performed? && copilot_user.feature_flag_enabled?(:copilot_signup_double_render_error, default: false)
      return
    end
    has_trade_restriction = copilot_user.user_object.has_commercial_interaction_restriction?(feature_type: :copilot)
    if !has_trade_restriction
      restrictor = Copilot::Authorization::TradeRestrictor.new(copilot_user)

      if GitHub.context.present? && restrictor.restricted?(GitHub.context, {})
        # they are restricted
        flash[:error] = "Unable to sign up for Copilot"
        render "copilot/signup_error", locals: {
          copilot_user: copilot_user,
          ci_path: preserve_tracking_params_path(copilot_pro_signup_path),
          form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_limited_user_path),
          eligible_for_trial: copilot_user.eligible_for_trial?,
          tracking_params: tracking_params,
          restricted: true,
        }, formats: :html
        return
      end

      Copilot::Instrumenter.instrument_signup_page_view(copilot_user, utm_query_params: utm_query_params)
      subscribe_limited_user
    else
      Copilot::Instrumenter.instrument_signup_page_view(copilot_user, utm_query_params: utm_query_params)

      render "copilot/signup_choice", locals: {
        has_trade_restriction:,
        copilot_user: copilot_user,
        ci_path: preserve_tracking_params_path(copilot_pro_signup_path),
        form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_limited_user_path),
        eligible_for_trial: copilot_user.eligible_for_trial?,
        tracking_params: tracking_params,
        restricted: false,
      }, formats: :html
    end
  end

  def free_signup # rubocop:todo GitHub/UseRestfulActions

    Copilot::Instrumenter.instrument_signup_free_page_view(copilot_user, utm_query_params: utm_query_params)

    render "copilot/free_signup", locals: {
      copilot_user: copilot_user,
      form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_free_user_path)
    }, formats: :html
  end

  def settings # rubocop:todo GitHub/UseRestfulActions
    if !signup_params[:public_code_suggestions] || signup_params[:public_code_suggestions] == ""
      return render "copilot/signup_success", locals: {
        copilot_user: copilot_user,
        error: true,
        error_message: "Please select an option for public code suggestions to enable Copilot",
        form_submit_path: preserve_tracking_params_path(copilot_signup_settings_path)
      }
    end

    old_settings = copilot_user.copilot_user_settings

    signup_params[:public_code_suggestions] == "allowed" ? copilot_user.allow_public_code_suggestions! : copilot_user.block_public_code_suggestions!
    signup_params[:telemetry] == "Allow" ? copilot_user.enable_telemetry! : copilot_user.disable_telemetry!
    signup_params[:copilot_policy_bing] == "enabled" ? copilot_user.bing_github_chat_enabled! : copilot_user.bing_github_chat_disabled!
    if signup_params[:a_chat] == "enabled"
      copilot_user.a_chat_enabled!
    elsif signup_params[:a_chat] == "disabled"
      copilot_user.a_chat_disabled!
    end

    if signup_params[:g_chat] == "enabled"
      copilot_user.g_chat_enabled!
    elsif signup_params[:g_chat] == "disabled"
      copilot_user.g_chat_disabled!
    end

    if signup_params[:g_tf] == "enabled"
      copilot_user.g_tf_enabled!
    elsif signup_params[:g_tf] == "disabled"
      copilot_user.g_tf_disabled!
    end

    if signup_params[:dashboard_entry_point] == "enabled"
      copilot_user.dashboard_entry_point_enabled!
    elsif signup_params[:dashboard_entry_point] == "disabled"
      copilot_user.dashboard_entry_point_disabled!
    end

    if signup_params[:overages] == "enabled"
      copilot_user.overages_enabled!
    elsif signup_params[:overages] == "disabled"
      copilot_user.overages_disabled!
    end

    if copilot_user.feature_flag_enabled?(:copilot_al, default: true) && Copilot::Users::ModelAccess.model_available?(copilot_user, :al)
      if signup_params[:al] == "enabled"
        copilot_user.al_enabled!
      elsif signup_params[:al] == "disabled"
        copilot_user.al_disabled!
      end
    end

    if copilot_user.feature_flag_enabled?(:copilot_afos, default: true) && Copilot::Users::ModelAccess.model_available?(copilot_user, :afos)
      if signup_params[:afos] == "enabled"
        copilot_user.afos_enabled!
      elsif signup_params[:afos] == "disabled"
        copilot_user.afos_disabled!
      end
    end

    if copilot_user.feature_flag_enabled?(:copilot_gtff, default: false) && Copilot::Users::ModelAccess.model_available?(copilot_user, :gtff)
      if signup_params[:gtff] == "enabled"
        copilot_user.gtff_enabled!
      elsif signup_params[:gtff] == "disabled"
        copilot_user.gtff_disabled!
      end
    end

    if copilot_user.feature_flag_enabled?(:copilot_obmb, default: false) && Copilot::Users::ModelAccess.model_available?(copilot_user, :obmb)
      if signup_params[:obmb] == "enabled"
        copilot_user.obmb_enabled!
      elsif signup_params[:obmb] == "disabled"
        copilot_user.obmb_disabled!
      end
    end

    if copilot_user.feature_flag_enabled?(:copilot_obmw, default: false) && Copilot::Users::ModelAccess.model_available?(copilot_user, :obmw)
      if signup_params[:obmw] == "enabled"
        copilot_user.obmw_enabled!
      elsif signup_params[:obmw] == "disabled"
        copilot_user.obmw_disabled!
      end
    end

    if copilot_user.feature_flag_enabled?(:copilot_ofct, default: false) && Copilot::Users::ModelAccess.model_available?(copilot_user, :ofct)
      if signup_params[:ofct] == "enabled"
        copilot_user.ofct_enabled!
      elsif signup_params[:ofct] == "disabled"
        copilot_user.ofct_disabled!
      end
    end

    if copilot_user.feature_flag_enabled?(:copilot_grok_code, default: false) && Copilot::Users::ModelAccess.model_available?(copilot_user, :grok_code)
      if signup_params[:grok_code] == "enabled"
        copilot_user.grok_code_enabled!
      elsif signup_params[:grok_code] == "disabled"
        copilot_user.grok_code_disabled!
      end
    end


    if copilot_user.feature_flag_enabled?(:copilot_aofo, default: false) && Copilot::Users::ModelAccess.model_available?(copilot_user, :aofo)
      if signup_params[:aofo] == "enabled"
        copilot_user.aofo_enabled!
      elsif signup_params[:aofo] == "disabled"
        copilot_user.aofo_disabled!
      end
    end

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
    render "copilot/signup_success", locals: { copilot_user: copilot_user, form_submit_path: preserve_tracking_params_path(copilot_signup_settings_path), error_message: nil }, formats: :html
  end

  def subscribe # rubocop:todo GitHub/UseRestfulActions
    if !signup_billing_valid
      flash[:error] = "Missing required parameters"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
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
      redirect_to preserve_tracking_params_path(copilot_signup_path)
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

    if trial_signup? && !valid_contact_email?
      flash[:error] = "Please enter a valid email address"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
      return
    end

    result = copilot_user.subscribe(duration)

    if result.ok?
      # Queue up an auth and capture check so we can find out whether the payment details are
      # valid before the trial ends
      if trial_signup? && current_user.feature_flag_enabled?(:copilot_billing_auth_and_capture_users, default: false)
        is_trusted = TrustTiers::Tier.for_billable_owner(copilot_user.user_object).tier <= TrustTiers::Tier::TRUSTED
        copilot_user.perform_auth_and_capture!(audit_log_reason: "trial_signup", delay: 1.minute) unless is_trusted
      end

      # this should be inside the subscribe
      Copilot::LimitedUser.find_by(user_id: copilot_user.id)&.destroy

      subscription = result.value { nil }

      Copilot::Instrumenter.instrument_signup_subscription_created(
        copilot_user,
        duration.to_s,
        subscription.free_trial_length.to_i, # trial length
        utm_query_params: utm_query_params
      )

      send_new_trial_signup_notifications if trial_signup?

      if copilot_user.is_technical_preview_user?
        tp_user = Copilot::TechnicalPreviewUser.find_by(user: copilot_user)
        tp_user.subscribe if tp_user.present?
      end

      redirect_path = session.delete(:copilot_signup_redirect) || copilot_immersive_path
      redirect_to preserve_tracking_params_path(redirect_path)
    else
      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(copilot_signup_path)
    end
  end

  def subscribe_free_user # rubocop:todo GitHub/UseRestfulActions
    result = copilot_user.subscribe_free_user
    if result.ok?
      Copilot::LimitedUser.find_by(user_id: copilot_user.id)&.destroy
      Copilot::Instrumenter.instrument_signup_free_subscription_created(copilot_user, utm_query_params: utm_query_params)
      if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, current_user, default: true)
        Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(current_user))
      end
      redirect_to preserve_tracking_params_path(copilot_signup_success_path)
    else
      flash[:error] = result.error.message
      redirect_to preserve_tracking_params_path(copilot_signup_path)
    end
  end

  def subscribe_limited_user # rubocop:todo GitHub/UseRestfulActions
    if performed? && copilot_user.feature_flag_enabled?(:copilot_signup_double_render_error, default: false)
      return
    end

    if current_user.is_enterprise_managed?
      flash[:error] = "Unable to sign up for GitHub Copilot Free"
      render "copilot/signup_error", locals: {
        copilot_user: copilot_user,
        ci_path: preserve_tracking_params_path(copilot_pro_signup_path),
        form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_limited_user_path),
        eligible_for_trial: copilot_user.eligible_for_trial?,
        tracking_params: tracking_params,
        restricted: true,
      }, formats: :html
      return
    end

    Copilot::Instrumenter.instrument_signup_limited_subscription_created(copilot_user, utm_query_params: utm_query_params)
    restrictor = Copilot::Authorization::TradeRestrictor.new(copilot_user)

    if GitHub.context.present? && restrictor.restricted?(GitHub.context, {})
      # they are restricted
      flash[:error] = "Unable to sign up for GitHub Copilot Free"
      render "copilot/signup_error", locals: {
        copilot_user: copilot_user,
        ci_path: preserve_tracking_params_path(copilot_pro_signup_path),
        form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_limited_user_path),
        eligible_for_trial: copilot_user.eligible_for_trial?,
        tracking_params: tracking_params,
        restricted: true,
      }, formats: :html
      return
    end

    # These are the default settings for a new Copilot Free user
    # Also some stuff from Copilot Pro signup
    old_settings = copilot_user.copilot_user_settings

    url_options = { host: GitHub.admin_host_name, protocol: "https" }
    staff_url = stafftools_user_copilot_settings_url(current_user, **url_options)
    blocked = copilot_user.block_if_sharing_payment_method_with_other_blocked_users!

    if blocked || current_user.spammy?
      if blocked
        copilot_user.send_abuse_notification(
          url: staff_url,
          is_trial_signup: trial_signup?,
          signed_up: false,
        )
      end
      flash[:error] = "Unable to sign up for GitHub Copilot Free"
      render "copilot/signup_error", locals: {
        copilot_user: copilot_user,
        ci_path: preserve_tracking_params_path(copilot_pro_signup_path),
        form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_limited_user_path),
        eligible_for_trial: copilot_user.eligible_for_trial?,
        tracking_params: tracking_params,
        restricted: false,
      }, formats: :html
      return
    end

    if copilot_user.shares_payment_method_with_blocked_user?
      copilot_user.send_abuse_notification(
        url: staff_url,
        is_trial_signup: trial_signup?,
        signed_up: true,
      )
    end

    result = if session[:skip_copilot_signup_email]
      copilot_user.subscribe_limited_user(skip_copilot_signup_email: true)
      session.delete(:skip_copilot_signup_email)
    else
      copilot_user.subscribe_limited_user
    end

    if result.ok?
      Copilot::Instrumenter.instrument_signup_settings_saved(
        copilot_user,
        old_settings: old_settings,
        new_settings: Copilot::User.new(current_user).copilot_user_settings,
        utm_query_params: utm_query_params
      )
      # Let's just force cache generation out of abundance of caution
      Copilot::User.new(current_user).create_copilot_settings_cache(Copilot::Public::User::CURRENT_VERSION)
      if FeatureFlag.vexi.enabled?(:copilot_instrument_copilot_license_or_billable_customer_change, current_user, default: true)
        Copilot::Instrumenter.instrument_copilot_license_or_billable_customer_change(Copilot::Public::User.new(current_user))
      end
      if signup_params[:return_to].nil?
        redirect_path = session.delete(:copilot_signup_redirect) || copilot_immersive_path
        redirect_to preserve_tracking_params_path(redirect_path)
      else
        target_url = signup_params[:return_to]
        if valid_redirect_url?(target_url)
          redirect_to preserve_tracking_params_path(target_url)
        else
          redirect_to "/error.html"
        end
      end
    else
      flash[:error] = result.error.message
      render "copilot/signup_error", locals: {
        copilot_user: copilot_user,
        ci_path: preserve_tracking_params_path(copilot_pro_signup_path),
        form_submit_path: preserve_tracking_params_path(copilot_signup_subscribe_limited_user_path),
        eligible_for_trial: copilot_user.eligible_for_trial?,
        tracking_params: tracking_params,
        restricted: false,
      }, formats: :html
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
      *PERMITTED_SIGNUP_PARAMS,
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
    redirect_to "/settings/copilot" and return if (copilot_user.has_signed_up? || copilot_user.is_enterprise_managed?) && !copilot_user.has_limited_access?

    # if a user can sign up for free, send them to free signup
    redirect_to preserve_tracking_params_path(copilot_free_signup_path) and return if copilot_user.can_signup_for_free?

    redirect_to preserve_tracking_params_path(copilot_pro_signup_path) and return if copilot_user.has_limited_access?
  end

  # Users can only navigate to free_signup if they are a free user
  def require_free_user
    return if copilot_user.can_signup_for_free?
    redirect_to preserve_tracking_params_path(copilot_signup_path)
  end

  def target_for_conditional_access
    # This is safe due to :login_required
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def resource_for_conditional_access
    return self unless logged_in?

    current_user
  end

  def preserve_tracking_params_path(to_path, additional_params = {})
    super(to_path, editor_utm_params.merge(additional_params))
  end

  def restrict_enterprise_access
    # if a user is on an enterprise subscription we want to redirect them to the copilot settings page
    if logged_in? && copilot_user.orgs_using_copilot_for_business.any?
      redirect_to "/settings/copilot"
    end
  end

  def check_copilot_administrative_block
    if copilot_user.administrative_blocked?
      flash[:error] = "Your account is unable to sign up for Copilot. Please contact Support"
      redirect_to preserve_tracking_params_path(copilot_signup_path)
    end
  end

  def restrict_multi_tenant_access
    # if a user is on a multi-tenant instance we want to redirect them to the copilot settings page
    redirect_to "/settings/copilot" if GitHub.multi_tenant_enterprise?
  end

  def editor_utm_params
    return {} unless override_utm_for_editor?

    { utm_source: params[:editor], utm_medium: "editor" }
  end

  def override_utm_for_editor?
    return false if params.key?(:utm_source) || params.key?(:utm_medium)

    request.query_parameters[:editor].present?
  end

  def utm_query_params
    tracked_utm_params.merge(editor_utm_params)
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

  def send_new_trial_signup_notifications
    MarketingFormsSubmissionJob.perform_later(form_name: "copilot-trial-new", raw_data: user_signup_contact_info_for_marketing)
  end

  def valid_contact_email?
    return false unless user_contact_info_params[:email].present?
    user_contact_info_params[:email].match?(UserEmail::MarketingDependency::EMAIL_REGEX)
  end

  def valid_redirect_url?(url)
    begin
      uri = URI.parse(url)
      # Allow relative URLs or URLs on the same host
      !uri.host || uri.host == request.host
    rescue URI::InvalidURIError
      false
    end
  end
end
