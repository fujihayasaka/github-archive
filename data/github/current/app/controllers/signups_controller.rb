# typed: false
# frozen_string_literal: true

class SignupsController < ApplicationController
  include AnalyticsHelper
  include Site::MicrosoftAnalyticsDependency
  include Signups::FeatureHelperDependency
  include Signups::SignupHelperDependency
  include Signups::CustomContentDependency
  include Signups::MarketingConsentDependency
  include Signups::SuggestedUsernamesDependency
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

  helper_method :signup_octocaptcha

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url]
  }

  def new
    user = User.new
    user.email = params[:user_email]

    signup_octocaptcha.set_test_group(params[:source])
    if FeatureFlag.vexi.enabled?(:track_social_signup_started, default: false) && is_social_signup?
      provider = session.dig(:user_social_identity, "provider")
      analytics_event(
        category: "Social Sign up",
        action: "Started - #{provider}",
        label: referral_labels("source:#{params[:source]};")
      )
      user.email = social_email
      signup_octocaptcha.instrument_event("social_signup_started")
    else
      signup_octocaptcha.instrument_event("signup_started")
    end
    captcha_demo = params[:captcha_demo] == "true"

    #https://github.com/github/special-projects/issues/528
    headers["Cache-Control"] = "no-cache, no-store"

    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Started",
      label: referral_labels("source:#{params[:source]};")
    ) if signup_octocaptcha.show_captcha?

    # Log all DataDome headers for debugging (case-insensitive search)
    if FeatureFlag.vexi.enabled?(:datadome_header_logging_enabled, default: false)
      # Sanity check: log a known header to verify logging is working
      log_data["gh.datadome.new.existing.user_agent"] = request.env["HTTP_USER_AGENT"]

      datadome_info_found = false
      request.env.each do |key, value|
        if key.to_s.downcase.include?("datadome")
          log_data["gh.datadome.new.#{key.downcase}"] = value
          datadome_info_found = true
        end
      end
      log_data["gh.datadome.info_found"] = datadome_info_found
    end

    render "signups/nux/new", locals: {
      user: user,
      captcha_demo: captcha_demo,
      enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled,
      actor_country_code: actor_country_code,
      custom_page_param: custom_page_param,
      social_signup_enabled: is_social_signup?,
      contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param),
      show_social_login_buttons: show_social_login_buttons?,
      start_with_captcha: start_with_captcha?,
    }
  end

  def create
    # Log all DataDome headers for debugging (case-insensitive search)
    if FeatureFlag.vexi.enabled?(:datadome_header_logging_enabled, default: false)
      # Sanity check: log a known header to verify logging is working
      log_data["gh.datadome.create.existing.user_agent"] = request.env["HTTP_USER_AGENT"]

      datadome_info_found = false
      request.env.each do |key, value|
        if key.to_s.downcase.include?("datadome")
          log_data["gh.datadome.create.#{key.downcase}"] = value
          datadome_info_found = true
        end
      end
      log_data["gh.datadome.info_found"] = datadome_info_found
    end

    if is_social_signup?
      return handle_social_error(:disabled, msg: "Sign-up with a social provider is not enabled.") unless GitHub.social_sisu_enabled?(user: previously_verified_anon_user)

      set_email_for_social
      if signup_params.dig(:user_hash, :email).blank?
        GitHub.logger.info(
            "Social signup missing email in session",
            "gh.request_id" => GitHub.context[:request_id],
            "user_agent.original" => request.user_agent.to_s,
            "provider" => session.dig(:user_social_identity, "provider")
          )
        return handle_social_error(:registration_missing)
      end
    end

    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :signup_redesign)
    octocaptcha.set_test_group(params[:source])
    octacaptcha_event_name = is_social_signup? ? "social_signup_attempt" : "signup_attempt"
    octocaptcha.instrument_event(octacaptcha_event_name,
      signup_time: signup_params.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
      email_address: signup_params.dig(:user_hash, :email),
      datadome_data_exchange: datadome_data_exchange_from_request
    )
    octocaptcha.verify

    if is_social_signup?
      provider = session.dig(:user_social_identity, "provider")
      analytics_event(
        category: "Social Sign up",
        action: "Attempt - #{provider}",
        label: referral_labels("source:#{params[:source]};")
      )
    end
    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Attempt",
      label: referral_labels("source:#{params[:source]};")
    ) if octocaptcha.show_captcha?

    user = User.new(signup_params[:user_hash])
    user.persistent_client_id = persistent_client_id
    user.solved_interactive_captcha = octocaptcha.solved_interactive_captcha?
    user.time_zone_name = Time.zone.name

    if octocaptcha.solved?
      report_captcha_submission_mismatches(octocaptcha, user)

      if FeatureFlag.vexi.enabled?(:error_loading_captcha_with_solved_token, default: false)
        report_error_loading_captcha_with_solved_token if params[:error_loading_captcha]
      end
    else
      if octocaptcha.solved_interactive_captcha?
        GitHub.dogstats.increment("signup_captcha.solved_puzzle_failed_validation")
        GitHub.logger.info(
          "Octocaptcha puzzle solved but verification failed",
          "gh.request_id" => GitHub.context[:request_id],
          "user_agent.original" => request.user_agent.to_s,
          "funcaptcha_session_id" => octocaptcha.funcaptcha_session_id,
          "funcaptcha_response" => octocaptcha.funcaptcha_response.to_s
        )
      end

      if params[:error_loading_captcha]
        GitHub.dogstats.increment("signup_captcha.error_loading_captcha", tags: ["full_form_submitted:true"])
        GitHub.logger.info(
          "Octocaptcha unable to load",
          "gh.request_id" => GitHub.context[:request_id],
          "user_agent.original" => request.user_agent.to_s
        )
      end

      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?

      punishment_action = nil
      if FeatureFlag.vexi.enabled?(:octocaptcha_punishment_error_messages, default: false) && octocaptcha.punished?
        punishment_action = octocaptcha.suggested_action
        GitHub.dogstats.increment(
          "signup_captcha.punishment_detected",
          tags: ["suggested_action:#{punishment_action}", "is_social_signup:#{is_social_signup?}"]
        )
      end

      return render "signups/nux/new", locals: {
        user: user,
        captcha_demo: params[:captcha_demo] == "true",
        social_email: is_social_signup? ? social_email : nil,
        captcha_error_message: captcha_error_message(punishment_action)
      }
    end

    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Solved",
      label: referral_labels("source:#{params[:source]};")
    ) if octocaptcha.show_captcha?

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

    if provider.blank?
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
    if FeatureFlag.vexi.enabled?(:social_signup_email_token, default: false)
      result[:social_email_token] = octocaptcha_social_email_token(email)
    end

    render json: result
  end

  private

  # Generate a signed email token for social signup
  # Uses a 10-minute TTL matching the social identity expiry
  # Token payload includes: email, flow, and iat (issued at timestamp)
  def octocaptcha_social_email_token(email)
    return nil if email.blank?

    payload = {
      "email" => email,
      "flow" => "social_signup",
      "iat" => Time.now.to_i, # issued-at (seconds)
    }

    verifier = Rails.application.message_verifier(:octocaptcha_social_email)
    verifier.generate(payload, expires_in: ::SocialLogin::OpenIdConfiguration::REQUEST_TIMEOUT, purpose: :social_signup)
  end

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
    return false if GitHub.single_or_multi_tenant_enterprise?
    return false if in_social_flow?
    return false if is_emu_login?
    return false if is_mobile_ios?

    true
  end

  def param_is_true?(param_name)
    params[param_name] == "true"
  end

  def datadome_data_exchange_from_request
    return {} unless FeatureFlag.vexi.enabled?(:datadome_js_tag_enabled, current_user || User.ghost, default: false)

    {
      "HEADER_x-datadome-requestid" => request.headers["HTTP_X_DATADOME_REQUESTID"],
      "HEADER_x-datadome-sessionid" => request.headers["HTTP_X_DATADOME_SESSIONID"],
      "HEADER_x-datadome-isbot" => request.headers["HTTP_X_DATADOME_ISBOT"],
      "HEADER_x-datadome-ruletype" => request.headers["HTTP_X_DATADOME_RULETYPE"],
      "HEADER_x-datadome-botname" => request.headers["HTTP_X_DATADOME_BOTNAME"],
      "HEADER_x-datadome-captchapassed" => request.headers["HTTP_X_DATADOME_CAPTCHAPASSED"],
      "HEADER_x-datadome-traffic-rule-response" => request.headers["HTTP_X_DATADOME_TRAFFIC_RULE_RESPONSE"],
      "HEADER_x-datadome-captchaurl" => request.headers["HTTP_X_DATADOME_CAPTCHAURL"],
      "HEADER_x-datadome-matchedmodels" => request.headers["HTTP_X_DATADOME_MATCHEDMODELS"],
    }.select { |_, value| value.present? }
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
    provider = session[:user_social_identity]["provider"]
    provider_id = ::SocialLogin::OpenIdConfiguration.provider_id(provider) if provider.present?
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
        analytics_event(
          category: "Social Sign up",
          action: "Success - #{provider}",
          label: referral_labels("source:#{params[:source]};")
        )
        octocaptcha.instrument_event("social_signup_success",
          signup_time: signup_params.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
          user: user,
          email_address: user_social_email.email,
          funcaptcha_response: octocaptcha.funcaptcha_response
        )
        signup_tasks_and_data_collection(user, user_social_email.email, country, marketing_consent_granted?)
        current_device = device_and_ip_updates(user)

        login_user user,
          authenticated_device: current_device,
          sign_in_verification_method: :social_sign_up,
          client: :sign_up
        @social_result = :signup_success

        conditional_free_copilot_license(user)
        flash[:skip_account_picker] = true
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
    GitHub.dogstats.increment("authentication.social_signup", tags: ["result:#{@social_result}", "vscode:#{is_vscode}", "provider:#{provider}"])
  end

  def handle_social_error(social_result, msg: "We encountered an issue using your social login provider. Please try again or use our alternative sign-in or sign-up options.", user: nil, redirect: true)
    @social_result = social_result
    provider = session[:user_social_identity].present? ? session[:user_social_identity]["provider"] : "unknown"
    if Rails.env.development?
      flash[:error] = msg
    else
      anonymous_flash[:error] = msg
    end
    GitHub.dogstats.increment("authentication.social_signup_error", tags: ["result:#{social_result}", "vscode:#{vscode_return_to}", "provider:#{provider}"])
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

  # Detects and reports mismatches between captcha data exchange and form submission data.
  # This is used for monitoring data integrity during the signup process.
  def report_captcha_submission_mismatches(octocaptcha, user)
    return unless octocaptcha.is_more_data_exchange_enabled.call

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
  end

  # Logs and tracks cases where the client reported a captcha load failure
  # but the captcha token was still successfully verified. This can occur
  # due to race conditions (slow/delayed iframe load followed by successful postMessage).
  def report_error_loading_captcha_with_solved_token
    GitHub.dogstats.increment("signup_captcha.error_loading_captcha_with_solved_token")
    GitHub.logger.info(
      "Octocaptcha error_loading_captcha flag set but token solved",
      "gh.request_id" => GitHub.context[:request_id],
      "user_agent.original" => request.user_agent.to_s,
      "octocaptcha_solved" => true
    )
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
    if FeatureFlag.vexi.enabled?(:social_signup_strong_params, default: false) && is_social_signup?
      params[:user].permit(:login)
    else
      params[:user].permit(
        :login,
        :email,
        :password,
      )
    end
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
    in_social_flow?
  end

  def set_email_for_social
    user_hash = signup_params[:user_hash]
    user_hash[:email] = social_email
  end

  sig { returns(String) }
  def social_email
    return "" unless is_social_signup?
    session.dig(:user_social_identity, "email") || ""
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

  # Private: Memoized octocaptcha for the signup NUX flow.
  def signup_octocaptcha
    Octocaptcha.new(session, page: :signup_redesign)
  end
  memoize :signup_octocaptcha

  CAPTCHA_ERRORS = {
    try_different_email: {
      heading: "This email can't be used",
      message: "We're unable to create an account with this email address. Please try again with a different email, or %{link} for assistance.",
    },
    try_different_domain: {
      heading: "This email domain can't be used",
      message: "Please use an email address from a different domain to create your account, or %{link} if you believe this is an error.",
    },
    try_again_later: {
      heading: "We couldn't create your account",
      message: "We detected unusual activity and are unable to complete your signup. Try again using a different network connection, or %{link} for help.",
    },
    blocked_no_action: {
      heading: "We couldn't create your account",
      message: "We detected unusual activity and are unable to complete your signup. Try again using a different network connection, or %{link} for help.",
    },
    default: {
      heading: "We couldn't create your account",
      message: "We're unable to complete your signup at this time. Please try again later or %{link} if the problem continues.",
    },
  }.freeze
  private_constant :CAPTCHA_ERRORS

  # Private: Generate the appropriate captcha error heading and message based on the punishment action.
  # Returns a hash with :heading and :message keys, where both are HTML-safe strings.
  def captcha_error_message(punishment_action)
    troubleshooting_url = "#{GitHub.help_url}/articles/troubleshooting-connectivity-problems/#troubleshooting-the-captcha"
    link = helpers.safe_link_to("view troubleshooting steps", troubleshooting_url, target: :_blank, class: "Link--inTextBlock")

    error = CAPTCHA_ERRORS.fetch(punishment_action, CAPTCHA_ERRORS[:default])
    heading = error[:heading].html_safe # rubocop:disable Rails/OutputSafety
    message = format(error[:message], link: link).html_safe # rubocop:disable Rails/OutputSafety

    { heading: heading, message: message }
  end
end
