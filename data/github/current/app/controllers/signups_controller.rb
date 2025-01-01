# typed: false
# frozen_string_literal: true

class SignupsController < ApplicationController
  include AnalyticsHelper
  include Site::MicrosoftAnalyticsDependency

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
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url],
  }

  def new
    octolytics_id = current_visitor.octolytics_id
    feature_flag_msg = if feature_enabled_for_current_visitor?(feature_name: :nux_signup_flow)
      "Current Visitor is an actor for nux_signup_flow feature flag"
    else
      "Current Visitor is not an actor for nux_signup_flow feature flag"
    end
    GitHub.logger.info(feature_flag_msg, "gh.octolytics.id": octolytics_id)

    user = User.new

    octocaptcha = Octocaptcha.new(session)
    octocaptcha.set_test_group(params[:source])
    octocaptcha.instrument_event("signup_started")
    captcha_demo = params[:captcha_demo] == "true"

    #https://github.com/github/special-projects/issues/528
    headers["Cache-Control"] = "no-cache, no-store"

    user.email = params[:user_email]

    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Attempt",
      label: referral_labels("source:#{params[:source]};")
    ) if octocaptcha.show_captcha?

    render "signups/nux/new", locals: {
      user: user,
      captcha_demo: captcha_demo,
      enable_msft_analytics: @cookie_consent_enabled && @microsoft_analytics_enabled,
      octolytics_id: octolytics_id,
      feature_flag_msg: feature_flag_msg,
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

    user = User.new(signup_params[:user_hash])
    user.persistent_client_id = persistent_client_id
    user.solved_interactive_captcha = octocaptcha.solved_interactive_captcha?
    user.time_zone_name = Time.zone.name

    octocaptcha.instrument_event("signup_attempt",
      signup_time: signup_params.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
      email_address: signup_params[:user_hash][:email],
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
        captcha_demo: params[:captcha_demo] == "true"
      }
    end

    accountless_email_verification(user, octocaptcha)
  end

  private

  def accountless_email_verification(user, octocaptcha)
    if user.valid?
      GitHub.dogstats.increment("accountless_user_signup", tags: ["status:success"])

      verification_id = if signups_preferences_enabled?
        User::AccountlessEmailVerification.create_and_send_verification_email(
          user: user,
          octocaptcha: octocaptcha,
          visitor_id: current_visitor.id,
          spamurai_form_signals: signup_params[:spamurai_form_signals],
          funcaptcha_data_exchange: GitHub.context[:funcaptcha_data_exchange].presence,
          explicit_marketing_consent: marketing_consent_granted?,
          country_code: country
        )
      else
        User::AccountlessEmailVerification.create_and_send_verification_email(
          user: user,
          octocaptcha: octocaptcha,
          visitor_id: current_visitor.id,
          spamurai_form_signals: signup_params[:spamurai_form_signals],
          funcaptcha_data_exchange: GitHub.context[:funcaptcha_data_exchange].presence
        )
      end

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
        merge_return_to_params({ new_signup: true }) if GitHub.flipper[:new_signup_return_to_param].enabled?
        redirect_to account_verifications_path(return_to: return_to)
      else
        redirect_to account_verifications_path(
          invitation_token: params[:invitation_token].presence,
          repo_invitation_token: params[:repo_invitation_token].presence
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
      render "signups/nux/new", locals: { user: user, captcha_demo: params[:captcha_demo] == "true"
      }
    end
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

    if GitHub.flipper[:octocaptcha_enforce_no_signup_mismatches].enabled?
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

  def validate_visitor_ip
    return if Rails.env.development?
    return if !GitHub.spamminess_check_enabled?

    if Spam.ip_is_denylisted?(request.remote_ip)
      redirect_to new_signup_path
    end
  end

  def redirect_external_auth
    redirect_to "/login" if GitHub.auth.external?
  end

  # Returns the user's marketing consent preference.
  # Will override the preference to `false` when user's chosen country is Canada, China, or South Korea.
  # Context: https://github.com/github/new-user-experience/issues/377
  sig { returns(T::Boolean) }
  def marketing_consent_granted?
    excluded_marketing_country_codes = Set.new(%w(CA CN KR))
    return false if excluded_marketing_country_codes.include?(country)

    params[:marketing_consent] == "1"
  end

  def signup_enabled?
    unless GitHub.signup_enabled?
      redirect_to(login_path)
    end
  end

  def signups_layout
    "layouts/signups_rebrand"
  end


  # Returns the country code of an actor's IP address or returns nil if the IP address cannot
  # be found or the country code is not in the list of marketing targeted countries.
  sig { returns(T.nilable(String)) }
  def actor_country_code
    # "100.255.255.255" is US
    actor_ip = Rails.env.development? ? "100.255.255.255" : remote_ip
    return unless actor_ip.present?

    country_code = GitHub::Location.look_up(actor_ip).dig(:country_code)
    ::TradeControls::Countries.marketing_targeted_country?(country_code) ? country_code : nil
  end

  # Returns the country code if the provided country parameter is recognized.
  #
  # @return [String, nil] the country code if recognized, or nil if the country is blank or unrecognized.
  def country
    return if params[:country].blank?

    # Only take the first two characters of the string and capitalize for normalization.
    country_code = params[:country][0, 2].upcase

    ::TradeControls::Countries.marketing_targeted_country?(country_code) ? country_code : nil
  end
end
