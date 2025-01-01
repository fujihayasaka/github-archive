# typed: false
# frozen_string_literal: true
class SignupController < ApplicationController
  set_statsd_sample_rate 0.01, only: [:username_check, :email_check]

  include AnalyticsHelper
  include BillingSettingsHelper
  include SignupHelper
  include SuggestedUsernamesHelper
  include ColorHelper

  include SignupInvitesMethods

  layout "application"
  javascript_bundle :sessions
  javascript_bundle :signup
  stylesheet_bundle :site
  stylesheet_bundle :signup

  include Site::MicrosoftAnalyticsDependency
  before_action :allow_initial_cookie_consent, only: [:join]
  before_action :enable_microsoft_analytics, only: [:join]
  before_action :add_microsoft_analytics_csp_exceptions, only: [:join]
  before_action :redirect_to_new_signup_feature_flagged, only: [:create_account]
  before_action :redirect_to_new_signup, only: [:join]
  layout "enterprise_funnel", only: [:join]

  # This controller does not access protected organization resources.
  skip_before_action :perform_conditional_access_checks # rubocop:disable GitHub/DoNotSkipCapBeforeAction
  before_action :disable_color_modes, except: [:get_started]
  before_action :set_return_to
  before_action :clear_weak_password_session_variable, only: :join
  before_action :login_required, except: [:join, :create_account, :username_check, :email_check, :enterprise_trial_redirect]
  before_action :anon_required,  only: [:join, :create_account]
  before_action :enterprise_access_login_redirect, only: [:join]
  before_action :restrict_enterprise_access, except: [:join]
  before_action :set_plan,  only: [:process_plan_selection, :select_plan, :plan, :billing]
  before_action :add_csp_exceptions, only: [:join, :create_account]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Ballast,
    ApplicationRecord::Mysql5,
    only: [:username_check]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:get_started]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    ApplicationRecord::Spokes,
    ApplicationRecord::Collab,
    only: [:join]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    only: [:enterprise_trial_redirect]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    only: [:zuora_payment_page_signature]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Billing,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Repositories,
    only: [:plan]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:billing]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:get_started, :plan, :billing],
    optional: true

  CSP_EXCEPTIONS = {
    frame_src: [GitHub.urls.octocaptcha_host_name],
  }

  CLUSTER_DEPENDENCIES_ALLOWED_NON_GET_REQUESTS = [
    "SignupController#username_check",
  ]

  after_action  :update_login_metadata, only: [:create_account]

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:username_check, :email_check],
    key: :signup_check_rate_limit_key,
    max: :signup_check_rate_limit_max,
    ttl: :signup_check_rate_limit_ttl,
    at_limit: :record_username_check_limit

  if enterprise?
    skip_before_action :first_run_check, only: %w( join create_account username_check email_check )
  end

  if GitHub.single_or_multi_tenant_enterprise?
    before_action :signup_enabled?, only: [:join, :create_account]
  end

  # shows the signup form.
  def join # rubocop:todo GitHub/UseRestfulActions
    @user = User.new

    octocaptcha = Octocaptcha.new(session)
    octocaptcha.set_test_group("join")
    octocaptcha.instrument_event("signup_started")
    @captcha_demo = params[:captcha_demo] == "true"

    repo = Repository.nwo(params[:source_repo]) if params[:source_repo].present?

    if repo.present? && repo.public?
      branch = params[:branch]
      @return_to = session[:return_to] = repository_path(repo, branch)

      if params_from_downloading_repo?
        filename = filename_for_zip_download(repo, branch)
        flash.now[:notice] = "Downloading #{filename}"
      end
    end

    render_signup_view
  end

  def get_started # rubocop:todo GitHub/UseRestfulActions
    render "signup/get_started"
  end

  def enterprise_trial_redirect # rubocop:todo GitHub/UseRestfulActions
    if logged_in?
      redirect_to new_organization_path(with_referral_params(plan: GitHub::Plan.business_plus))
    else
      redirect_to signup_path(with_referral_params(plan: GitHub::Plan.business_plus, setup_organization: true))
    end
  end

  # creates a new account.
  def create_account # rubocop:todo GitHub/UseRestfulActions
    redirect_to "/login" if GitHub.auth.external?
    octocaptcha = Octocaptcha.new(session, params["octocaptcha-token"])
    octocaptcha.set_test_group(params[:source])
    octocaptcha.instrument_event("signup_started")
    octocaptcha.verify

    analytics_event(
      category: "Octocaptcha-Signup",
      action: "Attempt",
      label: referral_labels("source:#{params[:source]};")
    ) if octocaptcha.show_captcha?

    full_form_submitted = true
    signup_data = nil
    private_session_id = session.id&.private_id
    signup_data_key = "UserSignupData:#{private_session_id}"

    if params[:user]
      signup_data = computed_signup_params
      @user = User.new(signup_data[:user_hash])
      octocaptcha.instrument_event("signup_attempt",
                                   signup_time: signup_data.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
                                   email_address: signup_data[:user_hash][:email],
                                  )

      if disallowed?(@user)
        GitHub.dogstats.increment("user", tags: ["action:create", "error:disallowed"])
        return render_signup_view
      end

      if password_confirmation_missing?(@user)
        @user.errors.add(:password, "confirmation can't be blank")
        return render_signup_view
      end

      if !@user.valid?
        flash.now[::CompromisedPassword::WEAK_PASSWORD_KEY] = @user.provided_weak_password?

        analytics_event(
          category: "Octocaptcha-Signup",
          action: "Failure",
          label: referral_labels("source:#{params[:source]};")
        ) if octocaptcha.show_captcha?

        return render_failed_user_signup(@user, signup_data.slice(:sso_organization, :invitation_token, :source))
      end

      signup_data[:user_hash].tap do |u|
        u[:password_hash] = GitHub::Password.create(u[:password]).to_s
        u.delete(:password)
        u.delete(:password_confirmation)
      end

      Users::Kv.store.set(signup_data_key, signup_data.to_json, expires: 10.minutes.from_now)
    else
      data = Users::Kv.store.get(signup_data_key).value { nil }
      if data
        full_form_submitted = false
        signup_data = JSON.parse(data).deep_symbolize_keys
        octocaptcha.instrument_event("signup_attempt",
                                     signup_time: signup_data.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
                                     email_address: signup_data[:user_hash][:email],
                                    )
      end
    end

    if signup_data.blank?
      return render_signup_view
    end

    if !octocaptcha.solved?
      @user = User.new
      @hide_signup_form = true

      if params[:error_loading_captcha]
        GitHub.dogstats.increment("signup_captcha.error_loading_captcha", tags: ["full_form_submitted:#{full_form_submitted}"])
        Failbot.report(
          Octocaptcha::UnableToLoadCaptcha.new,
          "app": "octocaptcha-errors",
          "gh.request_id": GitHub.context[:request_id],
          "user_agent.original": request.user_agent.to_s,
        )
        @octocaptcha_timeout = Octocaptcha::HIGHER_BROWSER_LOAD_TIMEOUT
        flash.now[:error] = "Unable to verify your captcha response. " \
          "Please visit #{GitHub.help_url}/articles/troubleshooting-connectivity-problems/#troubleshooting-the-captcha for troubleshooting information."
      end

      return render_signup_view
    end

    GitHub.context.push(visitor_id: current_visitor.id)
    GitHub.context.push(spamurai_form_signals: signup_data[:spamurai_form_signals])
    GitHub.context.push(funcaptcha_session_id: octocaptcha.funcaptcha_session_id)
    GitHub.context.push(funcaptcha_solved: octocaptcha.funcaptcha_solved)
    GitHub.context.push(funcaptcha_response: octocaptcha.funcaptcha_response)

    @user = User.new(signup_data[:user_hash])
    @user.solved_interactive_captcha = octocaptcha.solved_interactive_captcha?
    @user.time_zone_name = Time.zone.name

    # Allow staff users to create test accounts here without getting marked as spammy
    @user.mark_as_temporarily_exempt_from_spam_checks if user_exempt_from_spam_checks?

    if @user.save
      Users::Kv.store.del(signup_data_key)

      octocaptcha.instrument_event("signup_success",
                                   signup_time: signup_data.dig(:spamurai_signup_signals, :join_to_create_account_distance_in_milliseconds),
                                   user: @user.reload,
                                   email_address: signup_data[:user_hash][:email],
                                  )

      @user.queue_signup_tasks

      if suggested_username_used?(username: @user.display_login, suggested_usernames: params[:suggested_usernames])
        publish_suggested_username_event(
          user_id: @user.id,
          login: @user.display_login,
          suggestion_count: params[:suggested_usernames].count,
          action: SuggestedUsernamesHelper::EVENT_ACTIONS[:used],
        )
      end

      if !GitHub.enterprise?
        primary_email = @user.primary_user_email
        primary_email.toggle_visibility if primary_email.public?
      end

      @user.accept_tos
      @user.reload

      current_device = if @user.sign_in_analysis_enabled?
        # approve devices on new accounts by default
        @user.authenticated_devices.create!(
          accessed_at: Time.now,
          approved_at: Time.now,
          device_id: current_device_id,
          display_name: AuthenticatedDevice.generated_display_name(parsed_useragent),
        )
      end

      login_user @user, authenticated_device: current_device, sign_in_verification_method: :verified_device, client: :sign_up
      GlobalInstrumenter.instrument "user.signup.ip_update", {
        actor: @user,
        signup_email: @user.emails.first,
        actor_ip: @user.most_recent_session&.ip,
        actor_location: @user.most_recent_session&.location,
      }

      analytics_event(
        category: "Sign up",
        action: "Success",
        label: referral_labels("source:#{params[:source]};")
      )

      if octocaptcha.show_captcha?
        # If we render a page, then the first Attempt event in the beginning of the controller will fire
        # If we request redirect then this event will fire
        analytics_event(
          category: "Octocaptcha-Signup",
          action: "Attempt",
          label: referral_labels("source:#{params[:source]};")
        )

        analytics_event(
          category: "Octocaptcha-Signup",
          action: "Success",
          label: referral_labels("source:#{params[:source]};")
        )
      end

      set_analytics_dimension(
        name: GoogleAnalytics::Dimensions::HAS_ACCOUNT,
        value: "Signed Up",
        redirect: true,
      )

      if signup_data[:redeeming_coupon]
        redirect_to_return_to(fallback: signup_plan_path)
        return
      end

      # User signed up after going through the SSO flow for an organization.
      # Bounce the user back back to sign up action to link the identity.
      if signup_data[:sso_organization]
        redirect_to org_idm_sso_sign_up_path(signup_data[:sso_organization])
        return
      end

      # User signed up after going throug the SSO flow for a business.
      # Bounce the user back back to sign up action to link the identity.
      if signup_data[:sso_business]
        redirect_to business_idm_sso_sign_up_enterprise_path(signup_data[:sso_business])
        return
      end

      if signup_data[:invitation_token]
        process_org_invitation(signup_data[:invitation_token], @user)
        return if performed?
      end

      if signup_data[:repo_invitation_token]
        process_repo_invitation(signup_data[:repo_invitation_token], @user)
        return if performed?
      end

      if GitHub.billing_enabled?
        redirect_after_signup_completed(plan: signup_data[:plan], plan_duration: signup_data[:plan_duration], plan_selected: signup_data[:plan].present?) #skip plan selection
      else
        if signup_data[:setup_organization] && signup_data[:plan]
          redirect_to new_organization_path(plan: signup_data[:plan], plan_duration: signup_data[:plan_duration])
        else
          redirect_to_return_to(fallback: "/")
        end
      end
    else
      analytics_event(
        category: "Octocaptcha-Signup",
        action: "Failure",
        label: referral_labels("source:#{params[:source]};")
      ) if octocaptcha.show_captcha?

      render_failed_user_signup(@user, signup_data.slice(:sso_organization, :invitation_token, :source))
    end
  end

  def render_failed_user_signup(user, signup_data) # rubocop:todo GitHub/UseRestfulActions
    user.password = nil
    user.password_confirmation = nil
    GitHub.dogstats.increment("user", tags: ["action:create", "error:invalid"])

    analytics_event(
      category: "Sign up",
      action: "Failure",
      label: referral_labels("source:#{params[:source]};")
    )

    # If this request originated from an organization SSO flow,
    # render the organization SSO signup page.
    if signup_data[:sso_organization]
      view = create_view_model(
        Orgs::IdentityManagement::SingleSignOnView,
        organization: Organization.find_by_login(params[:sso_organization]),
      )
      render "orgs/identity_management/sign_up_via_sso", layout: "layouts/session_authentication", locals: { view: view }
      return
    end
    # If this request originated from an organization invitation via email,
    # render the organization invitation signup page.
    if (pending_invitation = pending_org_invitation(signup_data[:invitation_token]))
      view = create_view_model(
        Orgs::Invitations::ShowPendingPageView,
        invitation: pending_invitation,
      )
      render "orgs/invitations/sign_up_via_invitation", layout: "layouts/session_authentication", locals: { view: view }
      return
    end

    render_signup_view
  end

  # renders the form.
  def plan # rubocop:todo GitHub/UseRestfulActions
    return render_404 unless GitHub.billing_enabled?

    if params[:setup_organization]
      redirect_to org_plan_path(plan: params[:plan])
    elsif @plan.pro?
      redirect_to signup_billing_path(plan: params[:plan])
    else
      render "signup/plan", locals: {
        plan: @plan,
        free_pricing_model: free_pricing_model,
        business_pricing_model: business_pricing_model,
        business_plus_pricing_model: business_plus_pricing_model,
      }
    end
  end

  # Used by the redesign to redirect users to the billing page if they chose a paid plan.
  # Otherwise we process their selection as usual.
  def select_plan # rubocop:todo GitHub/UseRestfulActions
    if [GitHub::Plan::TEAM_FREE_PLAN_NAME, GitHub::Plan.business.name, GitHub::Plan.business_plus.name].include?(params[:plan])
      redirect_to new_organization_path(with_referral_params(plan: @plan.name))
    elsif @plan.pro?
      redirect_to signup_billing_path(plan: "pro")
    else
      process_plan_selection
    end
  end

  # After you create an account, you choose a plan (or keep it free).
  # POST solidifies your plan decision.
  def process_plan_selection # rubocop:todo GitHub/UseRestfulActions
    GitHub.dogstats.increment("user.plan_selection", tags: ["action:attempt", "plan:#{@plan.name}"])
    if @plan.name == "free"
      current_user.save
      flash[:analytics_location_params] = { target: "User", billing: false, plan: @plan.name }
      GitHub.dogstats.increment("user.plan_selection", tags: ["action:success", "plan:#{@plan.name}"])
      return redirect_after_signup_completed
    end

    if current_user.has_any_trade_restrictions?
      flash[:error] = sanctioned_by_ofac_message
      GitHub.dogstats.increment("user.plan_selection", tags: ["action:rejected", "plan:#{@plan.name}"])
      return redirect_to signup_plan_path
    end

    if no_payment_details?
      flash[:error] = "Missing billing information. " \
        "Make sure you’re using a supported browser.  Please visit #{GitHub.help_url}/articles/supported-browsers"
      GitHub.dogstats.increment("user.plan_selection", tags: ["action:rejected", "plan:#{@plan.name}"])
      return redirect_to signup_billing_path
    end

    # Let's do this

    target = current_user

    context = {
      note: "Added #{target.friendly_payment_method_name} during signup",
      actor: current_user,
      user: current_user,
    }

    GitHub.context.push(context)
    Audit.context.push(context)

    begin
      result = GitHub::Billing.signup(target, @plan.name, actor: current_user, payment_details: payment_details)
      if result.success?
        publish_billing_plan_changed_for(
          actor: current_user,
          user: target,
          new_seat_count: result.record.seats,
          new_plan_name: @plan.name,
          user_first_name: params[:user_first_name],
          user_last_name: params[:user_last_name],
        )

        if target.payment_method
          publish_payment_method_changed_for(
            actor: current_user,
            account: target,
            payment_method: target.payment_method,
          )
        end

      end
    rescue GitHub::Billing::CustomerAlreadyExistsError
      GitHub.dogstats.increment("user.plan_selection", tags: ["action:rejected", "plan:#{@plan.name}"])
      return redirect_after_signup_completed
    end

    if result.success?
      GitHub.dogstats.increment("user.plan_selection", tags: ["action:success", "plan:#{@plan.name}"])
      analytics_ec_purchase(current_user, target.subscription.discounted_price, "Signup")
      flash[:analytics_location_params] = { target: "User", billing: false, plan: @plan.name, action: "upgrade" }
      flash[:notice] = "Thanks so much for deciding to become a paying customer!"
      redirect_after_signup_completed
    else
      GitHub.dogstats.increment("user.plan_selection", tags: ["action:failed", "plan:#{@plan.name}"])
      context = {
        error: result.error_message.to_s,
        metadata: result.error_message.try(:metadata),
      }

      GitHub.context.push(context)
      Audit.context.push(context)

      analytics_event(category: "User", action: "plan onboard failure")

      flash.now[:error] = result.error_message.to_s

      render "signup/plan", locals: {
        plan: @plan,
        free_pricing_model: free_pricing_model,
        business_pricing_model: business_pricing_model,
        business_plus_pricing_model: business_plus_pricing_model,
      }
    end
  end

  def billing # rubocop:todo GitHub/UseRestfulActions
    if current_user.has_any_trade_restrictions?
      redirect_to(signup_plan_path)
    else
      render "signup/billing", locals: { plan: @plan }
    end
  end

  def zuora_payment_page_signature # rubocop:todo GitHub/UseRestfulActions
    preferred_color_mode = ColorMode.from_name(cookies[:preferred_color_mode])
    color_theme = active_color_mode(preferred_color_mode: preferred_color_mode)

    page_name = zuora_settings_compact_payment_page? ? :settings_compact : :sign_up

    payments_page = ::Billing::Zuora::HostedPaymentsPage.new(
      page_name:  page_name,
      target: current_user,
      color_theme: color_theme,
      host: request.host,
    )

    render json: payments_page.params
  end

  # Inline validation check for signing up
  def username_check # rubocop:todo GitHub/UseRestfulActions
    username = params[:value]
    Failbot.push(user: username) # Since errors will occur before account creation this won't count as EUII

    # create a temporary user with the provided username so we can run model validations on it
    user = User.new(login: username, persistent_client_id: persistent_client_id)
    # mark it as readonly so that any changes in this check cannot be saved accidentally
    user.readonly!
    # trigger validations - we only care about the login validation here (not password, email, or anything else)
    user.valid?

    login_errors = user.errors[:login]
    suggest_usernames = true
    respond_to do |format|
      format.html_fragment do
        if !login_errors.empty?
          if suggest_usernames?(login_errors: login_errors, suggest_usernames_param: suggest_usernames)
            suggested_usernames = get_username_suggestions(base_username: user.display_login)
          end
          return render partial: "signup/invalid_username", formats: :html, status: 422, locals: {
            error_message:  user.login_error_message,
            suggested_usernames: suggested_usernames,
            source: params[:source],
          }
        end

        render html: "#{user.display_login} is available."
      end
    end
  end

  # Inline validation check
  def email_check # rubocop:todo GitHub/UseRestfulActions
    respond_to do |format|
      format.html_fragment do
        user = User.new(email: params[:value])
        return head :ok unless !user.valid? && user.errors[:emails].any?

        sanctioned_email_errors = user.errors.where(:email, :sanctioned_email)
        disposable_email_errors = user.errors.where(:email, :disposable_email)

        if sanctioned_email_errors.any?
          email_error = ::TradeControls::Notices.sanctioned_domain_email_warning
        elsif disposable_email_errors.any?
          email_error = "Email #{UserEmail::GENERIC_DOMAIN_ERROR}"
        else
          email_error = "Email is invalid or already taken"
        end

        render body: email_error, status: 422, content_type: "text/fragment+html"
      end
    end
  end

  private

  def redirect_to_new_signup_feature_flagged
    if GitHub.flipper[:deprecate_legacy_signup].enabled?
      redirect_to_new_signup
    end
  end

  def redirect_to_new_signup
    if !GitHub.enterprise?
      is_enterprise_first_account = enterprise? && enterprise_first_run?
      return_to = if params[:setup_organization] && !is_enterprise_first_account
        { return_to: new_organization_path(plan: params[:plan], plan_duration: "year", trial_acquisition_channel: params[:trial_acquisition_channel]) }
      else
        {}
      end
      redirect_to nux_signup_index_path(return_to)
    end
  end

  def computed_signup_params
    root_params.tap do |p|
      p[:user_hash] = user_params
    end
  end

  def user_params
    params[:user].permit(:login,
      :email,
      :password,
      :password_confirmation,
      :public_keys,
      :coupon,
    ).merge(extra_user_params)
  end

  def extra_user_params
    {
      referral_code: (cookies["tracker"] || "direct"),
      last_ip: request.remote_ip,
      gh_role: ("staff" if enterprise? && enterprise_first_run?),
    }
  end

  def root_params
    params.slice(:sso_organization,
      :invitation_token,
      :repo_invitation_token,
      :redeeming_coupon,
      :setup_organization,
      :plan,
      :plan_duration,
      :source,
      :timestamp,
      :timestamp_secret,
      "octocaptcha-token",
      :return_to,
      :suggested_usernames,
      :enterprise_plan,
    ).merge(metadata_params)
  end

  def metadata_params
    {
      spamurai_signup_signals: {
        join_to_create_account_distance_in_milliseconds: spamurai_form_signals.load_to_submit_in_milliseconds,
      },
      spamurai_form_signals: spamurai_form_signals,
    }
  end

  def trial_acquisition_channel_params
    return {} unless params[:trial_acquisition_channel].present?

    { trial_acquisition_channel: params[:trial_acquisition_channel] }
  end

  def set_plan
    @plan = GitHub::Plan.find(params[:plan]) || GitHub::Plan.default_plan
  end

  def signup_enabled?
    unless GitHub.signup_enabled? || GitHub.enterprise_first_run?
      redirect_to(login_path)
    end
  end

  def render_signup_view
    render "signup/join", locals: { setup_organization: params[:setup_organization], plan: params[:plan] }
  end

  def disallowed?(user)
    return if !GitHub.spamminess_check_enabled? || Rails.env.development?
    Spam.ip_is_denylisted?(user.last_ip)
  end

  def password_confirmation_missing?(user)
    return unless GitHub.password_confirmation_required?
    user.password_confirmation.blank?
  end

  # Where do you go after you are done with sign up?
  def redirect_after_signup_completed(plan: nil, plan_selected: true, plan_duration: nil)
    analytics_event(
      category: "User",
      action: "plan onboard",
      label: referral_labels("plan:#{current_user.plan.display_name};")
    ) if plan_selected

    if params[:setup_organization] && current_user.spammy?
      flash[:error] = "Something went wrong. Please contact support."
      redirect_to "/support"
    elsif params[:setup_organization] && current_user.should_verify_email?
      redirect_to account_verifications_path(with_referral_params(plan: plan, plan_duration: plan_duration, setup_organization: params[:setup_organization], **trial_acquisition_channel_params))
    elsif params[:setup_organization]
      redirect_to new_organization_path(with_referral_params(plan: plan, plan_duration: plan_duration, **trial_acquisition_channel_params))
    elsif session[:return_to]&.include?("oauth")
      redirect_to account_verifications_path(return_to: session[:return_to])
    elsif mobile?
      redirect_to "/"
    else
      redirect_to(account_verifications_path(recommend_plan: ActiveModel::Type::Boolean.new.cast(params[:recommend_plan])))
    end
  end

  def signup_check_rate_limit_key
    case action_name
    when "username_check"
      "signup_controller.username_check:#{request.remote_ip}"
    when "email_check"
      "email-check:#{request.remote_ip}"
    end
  end

  def signup_check_rate_limit_max
    case action_name
    when "username_check"
      100
    when "email_check"
      GitHub.email_check_rate_limit
    end
  end

  def signup_check_rate_limit_ttl
    case action_name
    when "username_check"
      GitHub::RateLimitedRequest::LEGACY_DEFAULT_RATE_LIMIT_TTL
    when "email_check"
      GitHub.email_check_ttl
    end
  end

  def record_username_check_limit
    GitHub.dogstats.increment("rate_limited", tags: ["action:username_check"]) if action_name == "username_check"
  end

  def publish_payment_method_changed_for(actor:, account:, payment_method:)
    GlobalInstrumenter.instrument(
      "billing.payment_method.addition",
      actor_id: actor.id,
      account_id: account.id,
      payment_method_id: payment_method.id,
    )
  end

  def filename_for_zip_download(repo, branch)
    if repo && branch
      repo.archive_command(branch, "zip").filename
    end
  end

  def params_from_downloading_repo?
    params[:source] == "download" && params[:source_repo].present? && params[:branch].present?
  end

  # Staff users can temporarily avoid getting their test accounts flagged as spammy
  # by possessing a valid `staffonly` cookie in combination with a `skip_signup_spam_checks=yes` cookie
  def user_exempt_from_spam_checks?
    GitHub.employee_unicorn? &&
      GitHub::StaffOnlyCookie.read(cookies).present? &&
      cookies["skip_signup_spam_checks"] == "yes"
  end

  def free_pricing_model
    free_org = Organization.new(plan: GitHub::Plan.free)
    Billing::PlanChange::PerSeatPricingModel.new(free_org, seats: free_org.seats)
  end

  def business_pricing_model
    business_org = Organization.new(plan: GitHub::Plan.business)
    Billing::PlanChange::PerSeatPricingModel.new(business_org, seats: business_org.seats)
  end

  def business_plus_pricing_model
    default_org = Organization.new(plan: GitHub::Plan.default_plan)
    Billing::PlanChange::PerSeatPricingModel.new(default_org, seats: default_org.seats, new_plan: GitHub::Plan.business_plus)
  end

  def zuora_settings_compact_payment_page?
    params[:view_context] == "ORGANIZATION_SIGNUP" && (github_customer_terms? || standard_terms_of_service?)
  end

  def github_customer_terms?
    params[:target] == "organization" && params[:terms_of_service] == "corporate"
  end

  def standard_terms_of_service?
    params[:target] == "organization" && params[:terms_of_service] == "standard"
  end
end
