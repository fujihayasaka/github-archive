# typed: true
# frozen_string_literal: true

class AccountVerificationsController < ApplicationController
  include SignupInvitesMethods
  include Signups::FeatureHelperDependency
  include Signups::CustomContentDependency

  # required to be able to make requests to this endpoint from react apps using the verifiedFetch function
  include ApplicationController::VerifiedFetchDependency
  allow_verified_fetch only: [:create]

  before_action :ensure_email_verification_required
  before_action :add_csp_exceptions, only: :index

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::SignupFlow,
    only: [:index]

  CSP_EXCEPTIONS = {
    img_src: [GitHub.contentful_marketing_image_host_url],
    media_src: [SecureHeaders::PolicyManagement::SELF, GitHub.asset_host_url, GitHub.contentful_marketing_asset_host_url]
  }
  QUERY_PARAM_LIMIT = 50

  layout "layouts/signups_rebrand"

  javascript_bundle "signup"

  stylesheet_bundle "site"
  stylesheet_bundle "signup"

  include GitHub::RateLimitedRequest

  rate_limit_requests \
  max: 10,
  ttl: 1.hour,
  only: [:create],
  key: :launchcodes_rate_limit_key

  rate_limit_requests \
  max: 100,
  ttl: 1.hour,
  only: [:index],
  key: :launchcodes_rate_limit_key



  def index
    if params[SignupsMailer::LAUNCH_CODE_METRICS_PARAM].present?
      # Log when this page was opened via the button in the launch code email.
      GitHub.dogstats.increment("launch_code_verification.email_button_clicked")
    end

    user_email = if accountless_email_verification.present?
      UserEmail.new(email: accountless_email_verification.email, verification_token: accountless_email_verification.verification_token)
    else
      current_user.primary_user_email
    end

    GitHub.dogstats.increment("launch_code_verification.loaded")

    render "account_verifications/index", locals: {
      plan: params[:plan],
      user_email: user_email,
      custom_page_param: custom_page_param,
      contentful_custom_content_entry: contentful_custom_content_entry(custom_page_param)
    }
  end

  def create
    token = params[:launch_code]&.join("")

    if accountless_email_verification.present?
      GitHub.logger.info(
        "Accountless email verification creation started",
        "code.namespace": "AccountVerificationsController",
        "code.function": "create",
        "gh.actor.id": current_user&.id,
        "gh.accountless_email_verification.id": accountless_email_verification_id,
        "gh.request_id": request_id,
        "gh.octolytics.id": current_visitor.octolytics_id,
      )

      verify_accountless_email(token)
    else
      result = UserEmail::Verify.call(
        email_id: current_user.primary_user_email.id,
        token: token,
        owner: current_user,
      )

      if result.success?
        if params[:invitation_token]
          process_org_invitation(params[:invitation_token], current_user)
          return if performed?
        end

        if params[:repo_invitation_token]
          process_repo_invitation(params[:repo_invitation_token], current_user)
          return if performed?
        end

        if params[:setup_organization].present?
          redirect_to new_organization_path(with_referral_params(plan: params[:plan], plan_duration: params[:plan_duration], **trial_acquisition_channel_params))
        elsif return_to.present?
          redirect_to_return_to(fallback: dashboard_path)
        else
          flash[:notice] = "Your email was verified."
          safe_redirect_to params.fetch(:redirect, dashboard_path)
        end
      else
        # Log to Datadog so we have an idea how many times users run into
        # errors when trying to enter their launch code.
        GitHub.dogstats.increment("launch_code_verification.failure", tags: [
          "error:#{result.error}"
        ])

        if request.xhr?
          render partial: "account_verifications/error",
            status: :unprocessable_entity,
            locals: { error_message: result.error_message }
        else
          flash[:error] = result.error_message
          redirect_to account_verifications_path(with_referral_params(plan: params[:plan],
            plan_duration: params[:plan_duration],
            setup_organization: params[:setup_organization],
            trial_acquisition_channel: params[:trial_acquisition_channel],
            invitation_token: params[:invitation_token],
            repo_invitation_token: params[:repo_invitation_token],
            return_to: return_to,
            cpage: custom_page_param))
        end
      end
    end
  end

  private

  def accountless_email_verification_id
    GitHub.logger.info(
      "getting accountless_email_verification_id",
      "code.namespace": "AccountVerificationsController",
      "code.function": "accountless_email_verification_id",
      "gh.actor.id": current_user&.id,
      "gh.octolytics.id": current_visitor.octolytics_id,
      "gh.request_id": request_id,
      "gh.params.verification": params[:verification],
      "gh.session.accountless_email_verification_id": session[:accountless_email_verification_id],
    )
    # When verifying an accountless email via email message, the id is sent on verification param
    params[:verification].presence || session[:accountless_email_verification_id].presence
  end

  memoize def accountless_email_verification
    User::AccountlessEmailVerification.find_email_verification(accountless_email_verification_id)
  end

  def target_for_conditional_access
    :no_target_for_conditional_access # rubocop:disable GitHub/SpecifyTargetForConditionalAccess
  end

  def ensure_email_verification_required
    GitHub.logger.info(
      "code.namespace": "AccountVerificationsController",
      "code.function": "ensure_email_verification_required",
      "gh.actor.id": current_user&.id,
      "gh.octolytics.id": current_visitor.octolytics_id,
      "gh.accountless_email_verification.id": accountless_email_verification_id,
      "gh.accountless_email_verification.present": accountless_email_verification.present?
    )

    if accountless_email_verification_id.present?
      redirect_to home_path if !User::AccountlessEmailVerification.exists?(accountless_email_verification_id)
    else
      redirect_to home_path unless current_user&.should_verify_email?
    end
  end

  def verify_accountless_email(token)
    GitHub.logger.info(
      "Verifying accountless email. xhr request: #{request.xhr?}.",
      "code.namespace": "AccountVerificationsController",
      "code.function": "verify_accountless_email",
      "gh.actor.id": current_user&.id,
      "gh.accountless_email_verification.id": accountless_email_verification_id,
      "gh.accountless_email_verification.present": accountless_email_verification.present?
    )
    if AuthenticationLimit.at_any?(email_verification_login: accountless_email_verification.display_login, increment: true)
      return render status: :too_many_requests, plain: "Rate limited"
    end

    if token == accountless_email_verification.verification_token
      ActiveRecord::Base.connected_to(role: :writing) do
        create_user
      end
    else
      # Log to Datadog so we have an idea how many times users run into
      # errors when trying to enter their launch code.
      GitHub.dogstats.increment("launch_code_verification.failure", tags: [
        "error:verification_failed",
        "accountless_email_verification:true"
      ])

      if request.xhr?
        render json: { error: "Invalid launch code." }, status: :unprocessable_entity
      else
        flash[:error] = "Invalid launch code."
        redirect_to account_verifications_path(with_referral_params(plan: params[:plan],
          plan_duration: params[:plan_duration],
          setup_organization: params[:setup_organization],
          verification: params[:verification].presence,
          return_to: return_to,
          cpage: custom_page_param))
      end
    end
  end

  def create_user
    user = accountless_email_verification.create_user(persistent_client_id)

    if user.persisted?
      octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"], page: :signup_redesign)

      octocaptcha.instrument_event("signup_success",
        signup_time: accountless_email_verification.spamurai_form_signals&.load_to_submit_in_milliseconds,
        user: user,
        email_address: user.email,
        funcaptcha_response: accountless_email_verification.funcaptcha_response
      )
      user.queue_signup_tasks
      primary_email = user.reload_primary_user_email
      user.accept_tos
      user.reload

      if accountless_email_verification.country_code.present? && !accountless_email_verification.explicit_marketing_consent.nil?
        UserSignup.capture_user_signup_data(
          user: user,
          email: accountless_email_verification.email,
          country_code: accountless_email_verification.country_code,
          gave_explicit_marketing_consent: accountless_email_verification.explicit_marketing_consent
        )
      end

      current_device = if user.sign_in_analysis_enabled?
        # approve devices on new accounts by default
        user.authenticated_devices.create!(
          accessed_at: Time.now,
          approved_at: Time.now,
          device_id: current_device_id,
          display_name: AuthenticatedDevice.generated_display_name(parsed_useragent),
        )
      end

      GlobalInstrumenter.instrument "user.signup.ip_update", {
        actor: user,
        signup_email: user.emails.first,
        actor_ip: user.most_recent_session&.ip,
        actor_location: user.most_recent_session&.location,
      }

      # Login user directly if in development environment, otherwise ask user to sign in
      if Rails.env.development? && !ENV["SIGNUP_REDIRECT_TO_LOGIN"].present?
        login_user user,
          authenticated_device: current_device,
          sign_in_verification_method: :new_sign_up,
          client: :sign_up
      else
        accountless_signup_device(user, current_device)
        anonymous_flash[:notice] = "Your account was created successfully. Please sign in to continue"
      end

      if params[:invitation_token].presence || params[:repo_invitation_token].presence
        process_org_invitation(params[:invitation_token], user) #if params[:invitation_token].presence
        process_repo_invitation(params[:repo_invitation_token], user) # if params[:repo_invitation_token].presence

        return if performed?
      end

      if params[:setup_organization].present?
        redirect_to new_organization_path(with_referral_params(plan: params[:plan], plan_duration: params[:plan_duration], **trial_acquisition_channel_params))
      elsif return_to.present?
        redirect_to_return_to(fallback: dashboard_path)
      else
        flash[:notice] = "Your email was verified."
        safe_redirect_to params.fetch(:redirect, dashboard_path)
      end
    else
      render "signups/nux/new", locals: { user: user, captcha_demo: params[:captcha_demo] == "true" }
    end
  end

  def launchcodes_rate_limit_key
    "launchcodes-limit:#{logged_in? ? current_user.id : rate_limit_key_for_visitor }"
  end

  def rate_limit_key_for_visitor
    accountless_email_verification.verification_id.presence || rate_limit_key_by_ip
  end

  def trial_acquisition_channel_params
    return {} unless params[:trial_acquisition_channel].present?

    { trial_acquisition_channel: params[:trial_acquisition_channel] }
  end

  def custom_page_param
    params[:cpage].present? ? params[:cpage].to_s[0...QUERY_PARAM_LIMIT].strip : nil
  end
end
