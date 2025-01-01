# typed: false
# frozen_string_literal: true

class SignupsController < ApplicationController
  include AnalyticsHelper

  before_action :redirect_external_auth, only: [:create]
  before_action :validate_visitor_ip, only: [:create]
  before_action :add_csp_exceptions
  before_action :anon_required, only: [:new, :create]
  before_action :enterprise_access_login_redirect, only: [:new]
  before_action :restrict_enterprise_access, except: [:new]
  before_action :disable_color_modes
  before_action :set_return_to, only: [:new]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:new]

  if GitHub.multi_tenant_enterprise?
    before_action :signup_enabled?, only: [:new, :create]
  end

  layout "layouts/signups"

  javascript_bundle "signup-redesign"
  javascript_bundle "signup"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url],
  }

  def new
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

    render "signups/new", locals: { user: user, captcha_demo: captcha_demo }
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

      return render "signups/new", locals: {
        user: user,
        octocaptcha_timeout: Octocaptcha::HIGHER_BROWSER_LOAD_TIMEOUT,
      }
    end

    if visitor_feature_enabled?(:accountless_email_verification)
      accountless_email_verification(user, octocaptcha)
    else
      create_account(user, octocaptcha)
    end
  end

  private

  def accountless_email_verification(user, octocaptcha)
    if user.valid?
      GitHub.dogstats.increment("accountless_user_signup", tags: ["status:success"])

      email_preference = opt_in? ? "marketing" : "transactional"
      verification_id = User::AccountlessEmailVerification.create_and_send_verification_email(
        user: user, email_preference: email_preference, octocaptcha: octocaptcha, visitor_id: current_visitor.id,
        spamurai_form_signals: signup_params[:spamurai_form_signals], funcaptcha_data_exchange: GitHub.context[:funcaptcha_data_exchange].presence
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
        merge_return_to_params({ new_signup: true }) if GitHub.flipper[:new_signup_return_to_param].enabled?
        redirect_to account_verifications_path(return_to: return_to)
      else
        redirect_to account_verifications_path(recommend_plan: true, invitation_token: params[:invitation_token].presence, repo_invitation_token: params[:repo_invitation_token].presence)
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
      render "signups/new", locals: { user: user }
    end
  end

  def create_account(user, octocaptcha)
    GitHub.context.push(visitor_id: current_visitor.id)
    GitHub.context.push(spamurai_form_signals: signup_params[:spamurai_form_signals])
    GitHub.context.push(funcaptcha_session_id: octocaptcha.funcaptcha_session_id)
    GitHub.context.push(funcaptcha_solved: octocaptcha.funcaptcha_solved)
    GitHub.context.push(funcaptcha_response: octocaptcha.funcaptcha_response)

    if user.save
      user.queue_signup_tasks(invitation_token: params[:invitation_token], repo_invitation_token: params[:repo_invitation_token])
      primary_email = user.reload_primary_user_email
      primary_email.toggle_visibility if primary_email.public?
      user.accept_tos
      user.reload

      current_device = if user.sign_in_analysis_enabled?
        # approve devices on new accounts by default
        user.authenticated_devices.create!(
          accessed_at: Time.now,
          approved_at: Time.now,
          device_id: current_device_id,
          display_name: AuthenticatedDevice.generated_display_name(parsed_useragent),
        )
      end

      octocaptcha.instrument_event("signup_success",
        signup_time: signup_params.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
        user: user,
        email_address: signup_params[:user_hash][:email],
      )

      login_user user,
        authenticated_device: current_device,
        sign_in_verification_method: :new_sign_up,
        client: :sign_up
      GlobalInstrumenter.instrument "user.signup.ip_update", {
        actor: user,
        signup_email: user.emails.first,
        actor_ip: user.most_recent_session&.ip,
        actor_location: user.most_recent_session&.location,
      }

      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Success",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?
      analytics_event(
        category: "Sign up",
        action: "Success",
        label: referral_labels("source:#{params[:source]};")
      )

      set_email_preference

      if return_to.present?
        merge_return_to_params({ new_signup: true }) if GitHub.flipper[:new_signup_return_to_param].enabled?
        redirect_to account_verifications_path(return_to: return_to)
      else
        redirect_to account_verifications_path(recommend_plan: true, invitation_token: params[:invitation_token].presence, repo_invitation_token: params[:repo_invitation_token].presence)
      end
    else
      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?
      analytics_event(
        category: "Sign up",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      )
      render "signups/new", locals: { user: user }
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

  def set_email_preference
    GitHub.context.push(visitor_id: current_visitor.id)

    email_preference = opt_in? ? "marketing" : "transactional"
    UpdateNewsletterPreferenceJob.perform_later(current_user.id, email_preference, true)
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

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def opt_in?
    params[:opt_in].present?
  end

  def signup_enabled?
    unless GitHub.signup_enabled?
      redirect_to(login_path)
    end
  end
end
