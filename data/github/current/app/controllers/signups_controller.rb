# typed: false
# frozen_string_literal: true

class SignupsController < ApplicationController
  include AnalyticsHelper
  include Site::MicrosoftAnalyticsDependency
  include Signups::FeatureHelperDependency
  include Signups::SignupHelperDependency
  include Signups::CustomContentDependency
  include Signups::MarketingConsentDependency
  include SuggestedUsernamesHelper
  include WebauthnHelper

  # required to be able to make requests to this endpoint from client side using the verifiedFetch or verifiedFetchJSON functions
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:social_signup_info]

  # This controller does not access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :redirect_external_auth, only: [:create]
  before_action :validate_visitor_ip, only: [:create]
  before_action :add_csp_exceptions
  before_action :anon_required, only: [:new, :create]
  before_action :enterprise_access_login_redirect, only: [:new]
  before_action :restrict_enterprise_access, except: [:new]
  before_action :disable_color_modes
  before_action :set_return_to, only: [:new]
  before_action :ensure_visitor_cookie, only: [:new, :create]

  # Enable 1DS / MSFT analytics
  before_action :allow_initial_cookie_consent, only: [:new]
  before_action :enable_microsoft_analytics, only: [:new]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Ballast,
    ApplicationRecord::Authnd,
    only: [:new]

  if GitHub.multi_tenant_enterprise?
    before_action :signup_enabled?, only: [:new, :create]
  end

  layout :signups_layout

  javascript_bundle "signup"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url]
  }

  def new
    user = User.new
    octocaptcha = Octocaptcha.new(session)
    octocaptcha.set_test_group(params[:source])
    octocaptcha.instrument_event("signup_started")
    captcha_demo = params[:captcha_demo] == "true"

    #https://github.com/github/special-projects/issues/528
    headers["Cache-Control"] = "no-cache, no-store"

    set_social_session_values(params[:social_token]) if params[:social_token].present?

    user.email = params[:user_email]

    if is_social_signup? && user.email.blank?
      user.email = social_email
    end
    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Attempt",
      label: referral_labels("source:#{params[:source]};")
    ) if octocaptcha.show_captcha?

    render "signups/nux/new", locals: {
      user: user,
      captcha_demo: captcha_demo,
      enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled,
      actor_country_code: actor_country_code,
      custom_page_param: custom_page_param,
      social_signup_enabled: is_social_signup?,
      contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param),
      show_social_login_buttons: show_social_login_buttons?,
      show_dynamic_social_different_account_link: show_dynamic_social_different_account_link?,
      start_with_captcha: start_with_captcha?,
    }
  end

  def create
    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :signup_redesign)
    octocaptcha.set_test_group(params[:source])
    octocaptcha.instrument_event("signup_started")
    octocaptcha.verify

    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Attempt",
      label: referral_labels("source:#{params[:source]};")
    ) if octocaptcha.show_captcha?

    if is_social_signup?
      return handle_social_error(:disabled, msg: "Sign-up with a social provider is not enabled.") unless GitHub.social_sisu_enabled?(user: previously_verified_anon_user)
      set_email_and_password_for_social
    end

    user = User.new(signup_params[:user_hash])
    user.persistent_client_id = persistent_client_id
    user.solved_interactive_captcha = octocaptcha.solved_interactive_captcha?
    user.time_zone_name = Time.zone.name

    octocaptcha.instrument_event("signup_attempt",
      signup_time: signup_params.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
      email_address: signup_params[:user_hash][:email]
    )

    if !octocaptcha.solved? || captcha_and_submission_data_mismatched?(octocaptcha, user)
      if params[:error_loading_captcha]
        GitHub.dogstats.increment("signup_captcha.error_loading_captcha", tags: ["full_form_submitted:true"])
        Failbot.report(
          Octocaptcha::UnableToLoadCaptcha.new,
          "app": "octocaptcha-errors",
          "gh.request_id": GitHub.context[:request_id],
          "user_agent.original": request.user_agent.to_s,
        )
      end

      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?

      user.errors.add(:base,
        "Unable to verify your captcha response. " \
        "Please visit #{GitHub.help_url}/articles/troubleshooting-connectivity-problems/#troubleshooting-the-captcha for troubleshooting information."
      )

      return render "signups/nux/new", locals: {
        user: user,
        captcha_demo: params[:captcha_demo] == "true",
        social_email: is_social_signup? ? social_email : nil
      }
    end

    # Analytics to track if the country selected by the user matches the suggested country.
    GitHub.dogstats.increment("signup.country_selector", tags: [
      "matches_default:#{country_selector_match?(params, actor_country_code)}",
      "social_signup:#{is_social_signup?}",
    ])

    if !is_social_signup?
      accountless_email_verification(user, octocaptcha)
    else
      verify_email_and_register_social_identity(user, octocaptcha)
    end
  end

  def social_signup_info # rubocop:todo GitHub/UseRestfulActions
    result = { email: nil, suggested_username: nil }

    unless is_social_signup?
      render json: result and return
    end

    email = social_email
    provider = session.dig(:user_social_identity, "provider")

    if email.blank?
      handle_social_error(
        :registration_missing,
        msg: "An unexpected error occurred during social sign-up, please try again or contact support.",
        redirect: false
      )
      render json: result and return
    end

    if show_dynamic_social_different_account_link? && provider.blank?
      handle_social_error(
        :provider_missing,
        msg: "An unexpected error occurred during social sign-up, please try again or contact support.",
        redirect: false
      )
      render json: result and return
    end
    result[:email] = email
    result[:suggested_username] = get_suggested_username(email:)
    result[:provider] = provider&.capitalize

    render json: result
  end

  private

  sig { returns(T::Boolean) }
  def start_with_captcha?
    return false unless is_social_signup?
    return false unless params[:get_started_with].to_s == "copilot-vscode"
    FeatureFlag.vexi.enabled?(:signup_start_with_captcha, default: false)
  end

  # Check if the country code selected by the user matches the suggested country code (actor_country_code).
  # This is only for analytics purposes, not for validation.
  sig { params(params: ActionController::Parameters, default_country_code: T.nilable(String)).returns(T.nilable(T::Boolean)) }
  def country_selector_match?(params, default_country_code)
    return nil unless params.dig(:user_signup, :country) && default_country_code

    params.dig(:user_signup, :country) == default_country_code
  end

  def get_suggested_username(email:)
    return "" if email.blank?
    return "" unless email.include?("@")
    base_username = email.split("@").first
    social_username_suggestion = get_username_suggestions(base_username:).first
  end

  sig { returns(T::Boolean) }
  def show_social_login_buttons?
    return false unless FeatureFlag.vexi.enabled?(:show_social_signup_buttons, default: false)
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless FeatureFlag.vexi.enabled?(:social_signup, default: false)
    return false if in_social_flow?
    return false if is_emu_login?
    return false if is_mobile_ios?

    true
  end

  def param_is_true?(param_name)
    params[param_name] == "true"
  end

  # Helper to check if the user is in the social signup flow
  def in_social_flow?
    param_is_true?(:social)
  end

  # Helper to check if the user is in the EMU login flow
  def is_emu_login?
    param_is_true?(:is_emu_login)
  end

  # Helper to check if the user is on iOS mobile
  def is_mobile_ios?
    param_is_true?(:mobile_ios)
  end

  def accountless_email_verification(user, octocaptcha)
    if user.valid?
      GitHub.dogstats.increment("accountless_user_signup", tags: ["status:success"])

      verification_id = User::AccountlessEmailVerification.create_and_send_verification_email(
          user: user,
          octocaptcha: octocaptcha,
          visitor_id: current_visitor.id,
          spamurai_form_signals: signup_params[:spamurai_form_signals],
          funcaptcha_data_exchange: GitHub.context[:funcaptcha_data_exchange].presence,
          explicit_marketing_consent: marketing_consent_granted?,
          country_code: country
        )

      session[:accountless_email_verification_id] = verification_id
      GitHub.logger.info(
        "Accountless user signed up successfully, redirecting to account_verifications_path",
        "code.namespace": "SignupsController",
        "code.function": "accountless_email_verification",
        "gh.accountless_email_verification.id": verification_id,
        "gh.session.accountless_email_verification_id": session[:accountless_email_verification_id],
        "gh.request_id": request_id,
      )

      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Success",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?
      analytics_event(
        category: "Accountless Sign up",
        action: "Success",
        label: referral_labels("source:#{params[:source]};")
      )

      if return_to.present?
        merge_return_to_params({ new_signup: true }) if FeatureFlag.vexi.enabled?(:new_signup_return_to_param, default: false)
        redirect_to account_verifications_path(return_to: return_to, get_started_with: custom_page_param.presence)
      else
        redirect_to account_verifications_path(
          invitation_token: params[:invitation_token].presence,
          repo_invitation_token: params[:repo_invitation_token].presence,
          get_started_with: custom_page_param.presence
        )
      end
    else
      GitHub.dogstats.increment("accountless_user_signup", tags: ["status:failure"])
      GitHub.logger.info(
        user.errors.full_messages.join(", "),
        "code.namespace": "SignupsController",
        "code.function": "accountless_email_verification",
        "gh.request_id": request_id,
      )

      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?
      analytics_event(
        category: "Accountless Sign up",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      )

      render "signups/nux/new", locals: {
        user: user,
        captcha_demo: params[:captcha_demo] == "true",
        social_email: is_social_signup? ? social_email : nil
      }
    end
  end

  def verify_email_and_register_social_identity(user, octocaptcha)
    @social_result = :generic_error
    return handle_social_error(:registration_missing) if !session[:user_social_identity].present?
    return handle_social_error(:registration_expired, msg: "Your request has expired. Please try again.") if session[:user_social_identity]["expires_at"].to_time.past?
    provider_id = ::SocialLogin::OpenIdConfiguration.provider_id(session[:user_social_identity]["provider"]) if session[:user_social_identity]["provider"].present?
    return handle_social_error(:invalid_provider) if provider_id.nil?

    begin
      GitHub.context.push(visitor_id: current_visitor.id)
      GitHub.context.push(spamurai_form_signals: signup_params[:spamurai_form_signals])
      GitHub.context.push(funcaptcha_session_id: octocaptcha.funcaptcha_session_id)
      GitHub.context.push(funcaptcha_solved: octocaptcha.funcaptcha_solved)
      GitHub.context.push(funcaptcha_response: octocaptcha.funcaptcha_response)

      user.persistent_client_id = persistent_client_id
      user.time_zone_name = Time.zone.name
      # creates the user account and verifies the email
      user_social_email = user.emails.first
      user_social_email.verify!
      resp = SocialIdentities.domain.register_social_identity(provider_id, session[:user_social_identity]["subject"], user.id, user_social_email.id, user_social_email.email)
      is_vscode = vscode_return_to
      if resp.result == :RESULT_SUCCESS
        signup_tasks_and_data_collection(user, user_social_email.email, country, marketing_consent_granted?)
        current_device = device_and_ip_updates(user)

        login_user user,
          authenticated_device: current_device,
          sign_in_verification_method: :social_sign_up,
          client: :sign_up
        @social_result = :signup_success

        conditional_free_copilot_license(user)
        flash[:skip_account_picker] = true if FeatureFlag.vexi.enabled?(:social_skip_account_picker, default: false)
        redirect_to_return_to(fallback: "/")
      else
        handle_social_error(:registration_failure, user: user)
      end
    rescue ActiveRecord::RecordInvalid, ActiveRecord::RecordNotSaved => e
      GitHub.logger.info(e.message, "code.namespace": "SignupsController", "code.function": "verify_email_and_register_social_identity", "gh.request_id": request_id)
      handle_social_error(:email_verification_failed, msg: "Failed to create your account. Please try again or use our alternative sign-in or sign-up options.", user: user)
    rescue Authnd::Proto::Error, Faraday::Error => e
      handle_social_error(:authnd_error, user: user)
    end
  ensure
    GitHub.dogstats.increment("authentication.social_signup", tags: ["result:#{@social_result}", "vscode:#{is_vscode}"])
  end

  def handle_social_error(social_result, msg: "We encountered an issue using your social login provider. Please try again or use our alternative sign-in or sign-up options.", user: nil, redirect: true)
    @social_result = social_result
    if Rails.env.development?
      flash[:error] = msg
    else
      anonymous_flash[:error] = msg
    end
    GitHub.dogstats.increment("authentication.social_signup_error", tags: ["result:#{social_result}"])
    # If we fail to register the social identity, we are currently deleting the user
    # to prevent the user from being left in a state where they have a GH account without a password.
    # We will revisit this in the account accural work: https://github.com/github/authentication/issues/4733
    # Set the "social_signup_delete" role when we don't want to send an email notification
    if user&.persisted?
      user&.update_attribute :gh_role, "social_signup_delete"
      user&.destroy
    end
    session.delete(:user_social_identity)
    redirect_to_login(params[:return_to]) if redirect
  end

  def captcha_and_submission_data_mismatched?(octocaptcha, user)
    return false unless octocaptcha.is_more_data_exchange_enabled.call

    data_exchange_blob = octocaptcha.funcaptcha_response.dig("session_details", "optional", "blob")
    data_exchange = Octocaptcha.decode_and_decrypt_dx_payload(data_exchange_blob)
    GitHub.context.push(funcaptcha_data_exchange: data_exchange)
    submission = { "login" => user.display_login, "email_address" => user.email }
    submission.merge!(Octocaptcha.extra_data_exchange_fields(request, GitHub.context.to_hash))

    mismatches = submission.filter_map do |key, value|
      key if data_exchange[key] != value
    end

    if mismatches.any?
      tags = mismatches.map { |k| "#{k}:true" }
      GitHub.dogstats.increment("signup_captcha.captcha_and_submission_data_mismatched", tags: tags)
    end

    if FeatureFlag.vexi.enabled?(:octocaptcha_enforce_no_signup_mismatches, default: false)
      return true if mismatches.include?("login")
      return true if mismatches.include?("email_address")
    end

    false
  end

  memoize def signup_params
    root_params.tap do |p|
      p[:user_hash] = user_params.merge(extra_user_params)
    end
  end

  def root_params
    params.slice(
      :timestamp,
      :timestamp_secret,
      "octocaptcha-token",
    ).merge(metadata_params)
  end

  def user_params
    params[:user].permit(
      :login,
      :email,
      :password,
    )
  end

  def extra_user_params
    {
      referral_code: (cookies["tracker"] || "direct"),
      last_ip: request.remote_ip,
      gh_role: ("staff" if enterprise? && enterprise_first_run?),
    }
  end

  def metadata_params
    {
      spamurai_signup_signals: {
        join_to_create_account_distance_in_milliseconds: spamurai_form_signals.load_to_submit_in_milliseconds,
      },
      spamurai_form_signals: spamurai_form_signals,
    }
  end

  # social_signup is the top level FF gate for the cached GET requests
  # social_sisu is the user specific FF checked during the create POST
  sig { returns(T::Boolean) }
  def is_social_signup?
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false unless in_social_flow?
    FeatureFlag.vexi.enabled?(:social_signup, default: false)
  end

  def show_dynamic_social_different_account_link?
    return false unless is_social_signup?
    FeatureFlag.vexi.enabled?(:show_dynamic_social_different_account_link, default: false)
  end

  # Temporary while we wait for the form to be able to submit meaningful data
  def set_email_and_password_for_social
    user_hash = signup_params[:user_hash]
    return unless user_hash[:password].blank?
    user_hash[:email] = social_email

    unless FeatureFlag.vexi.enabled?(:social_passwordless, default: false)
      random_password = SecureRandom.hex(32)
      user_hash[:password] = GitHub::Password.create(random_password).to_s[
        ...GitHub.password_maximum_length
      ]
    end
  end

  sig { returns(String) }
  def social_email
    return "" unless is_social_signup?
    session.dig(:user_social_identity, "email") || ""
  end

  sig { params(id: String).returns(T::Hash[String, T.untyped]) }
  def set_social_session_values(id)
    if is_social_signup?
      social_info = GitHub::Authentication::KV.store.get("#{SocialLogin::OpenIdConfiguration::SIGNUP_KV_IDENTIFIER}:#{id}").value! { nil }
      session[:user_social_identity] = social_info ? JSON.parse(social_info) : {}
    else
      session[:user_social_identity] = {}
    end
  end

  def validate_visitor_ip
    return if Rails.env.development?
    return if !GitHub.spamminess_check_enabled?

    if Spam.ip_is_denylisted?(request.remote_ip)
      redirect_to new_signup_path(get_started_with: custom_page_param)
    end
  end

  def redirect_external_auth
    redirect_to "/login" if GitHub.auth.external?
  end

  def signup_enabled?
    unless GitHub.signup_enabled?
      redirect_to(login_path, get_started_with: custom_page_param)
    end
  end

  def signups_layout
    "layouts/signups_rebrand"
  end

  # Private: Ensure the _octo cookie is set for visitor tracking when the feature flag is enabled.
  def ensure_visitor_cookie
    return unless FeatureFlag.vexi.enabled?(:nux_current_visitor_cookie, default: false)

    current_visitor # This will create the visitor and set the _octo cookie if it doesn't exist
  end
end
