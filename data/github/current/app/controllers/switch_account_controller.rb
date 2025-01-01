# typed: true
# frozen_string_literal: true

class SwitchAccountController < ApplicationController
  layout "layouts/session_authentication"
  javascript_bundle :sessions

  include FeatureFlagHelper
  include OauthHelper
  include EnterpriseManagedUsersHelper
  include ApplicationController::VerifiedFetchDependency

  allow_verified_fetch only: [:update]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Mysql5,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Repositories,
    only: [:index]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::Mysql5,
    ApplicationRecord::NotificationsEntries,
    only: [:oauth_select_account, :device_authorization_select_account]

  depends_on_clusters ApplicationRecord::Copilot,
    only: [:index, :oauth_select_account, :device_authorization_select_account],
    optional: true

  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  before_action :require_account_switcher_enabled, except: [:oauth_select_account, :device_authorization_select_account]
  before_action :authorization_required, only: [:oauth_select_account, :device_authorization_select_account]

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: :update,
    max: :update_rate_limit_max,
    ttl: :update_rate_limit_ttl,
    key: :update_rate_limit_key,
    log_key: "switch_account",
    at_limit: :at_update_rate_limit

  def index
    GitHub.dogstats.distribution_time("account_switcher.list_accounts.dist.duration") do
      # show this page if the user has any sessions (valid or invalid) stashed
      if !(logged_in? || account_switcher_helper.stashed_accounts.any?)
        GitHub.dogstats.increment("account_switcher.list_accounts", tags: [
          "result:redirected",
          "reason:no_stashed_accounts"
        ])
        return redirect_to_login
      end
      GitHub.dogstats.increment("account_switcher.list_accounts", tags: [
        "result:rendered"
      ])

      return_to_url = params[:return_to] || request.referrer
      render "sessions/switch_account", { locals: { return_to: return_to_url } }
    end
  end

  def update
    target_session_id = params[:user_session_id]&.to_i
    return bad_update_request("reason:missing_session_id") unless target_session_id

    target_stashed_account = account_switcher_helper.stashed_accounts.valid.find do |account|
      account.user_session&.id == target_session_id
    end
    return bad_update_request("reason:session_not_stashed") unless target_stashed_account

    if is_enterprise_access_restricted?(target_stashed_account.user.display_login)
      return respond_to do |format|
        format.html { render plain: enterprise_access_verification_message(business_from_header), status: :forbidden }
        format.json { render json: { error: enterprise_access_verification_message(business_from_header), reason: "enterprise access denied" }, status: :forbidden }
      end
    end

    target_user = target_stashed_account.user
    target_session = target_stashed_account.user_session
    if target_user.is_emu_and_not_first_owner? && !target_session&.external_identity_sessions&.active&.any?
      # require EMUs to go through Enterprise SSO when switching accounts if they don't have an active external identity session
      GitHub.dogstats.increment("account_switcher.switch_account", tags: ["result:failed", "reason:emu_sso_required"])

      redirect_to_url = business_idm_sso_enterprise_path(
        target_user.enterprise_managed_business,
        return_to: params[:return_to],
        # without the add_account param, if the user is trying to switch to an account
        # within the same enterprise and their _current_user_ is still active SSO'd,
        # they'll just get redirected to the home page instead of the SSO flow (since the code assumes they're already signed in for the enterprise)
        # ref: https://github.com/github/authentication/issues/4086
        add_account: "1",
      )

      return respond_to do |format|
        format.html do
          return safe_redirect_to redirect_to_url
        end
        format.json do
          render json: { success: false, reason: :emu_sso_redirect, redirect_to: redirect_to_url }
        end
      end
    end

    current_user_id = logged_in? ? current_user.id : nil
    login_user(
      target_user,
      existing_session: target_stashed_account.user_session,
      existing_session_key: target_stashed_account.user_session_key,
      sign_in_verification_method: nil,
    )

    GitHub.dogstats.increment("account_switcher.switch_account", tags: ["result:success"])

    respond_to do |format|
      format.html do
        flash[:stale_session_signedin] = "SWITCHED:#{current_user_id}:#{target_stashed_account.user.id}"
        safe_redirect_to params[:return_to]
      end
      format.json { render json: { success: true, return_to: params[:return_to] } }
    end
  end

  # rubocop:todo GitHub/UseRestfulActions
  def oauth_select_account
    application = get_application(params[:client_id])

    return render_404 if application.nil?

    unless select_account_required_for_oauth?(application)
      return redirect_to oauth_request_path(account_picker_params)
    end

    # Ensure logout and log back in skips account picker as well
    updated_params = account_picker_params.merge({ skip_account_picker: "true" })

    # Prevent an infinite loop by removing select_account
    if updated_params[:prompt] == "select_account"
      updated_params = updated_params.except(:prompt)
    end
    return_to_target = oauth_select_account_path(updated_params)

    render "oauth/account_picker", layout: "layouts/session_authentication", locals: {
      application: application,
      account_picker_params: updated_params,
      return_to_target: return_to_target
    }
  end

  # rubocop:todo GitHub/UseRestfulActions
  def device_authorization_select_account

    unless select_account_required_for_device_authorization?
      return redirect_to user_code_prompt_path({ skip_account_picker: "true" })
    end


    render "device_authorization/account_picker", layout: "layouts/device_authorization", locals: {
      # Ensure logout and log back in skips account picker as well
      return_to_target: device_authorization_select_account_path({ skip_account_picker: "true" })
    }
  end

  # Public: Continue forward with the device authorization flow with a given account chosen by the user.
  #
  # POST - Handle the form POST to set that the user has chosen an account to continue with.
  #
  # Redirects to the user_code_prompt_path with the original params and an account picker state param,
  # preventing the account picker from re-appearing.
  def device_authorization_selected_account # rubocop:todo GitHub/UseRestfulActions
    redirect_to user_code_prompt_path({ skip_account_picker: "true" })
  end

  private

  def require_account_switcher_enabled
    return render_404 unless account_switcher_helper.enabled?
  end

  def update_rate_limit_key
    if logged_in?
      "switch_account:update:#{current_user.id}"
    else
      "switch_account:update:#{request.remote_ip}"
    end
  end

  private def apply_weaker_rate_limit?
    logged_in? || account_switcher_helper.stashed_accounts.valid.any?
  end


  def update_rate_limit_max
    apply_weaker_rate_limit? ? 100 : 10
  end

  def update_rate_limit_ttl
    apply_weaker_rate_limit? ? 30.minutes : 1.hour
  end

  def at_update_rate_limit
    GitHub.dogstats.increment("account_switcher.switch_account", tags: [
      "result:failed",
      "reason:rate_limited"
    ])
  end

  def select_account_required_for_oauth?(application)
    if current_user
      skip_account_picker = params[:skip_account_picker] == "true"
      return false if skip_account_picker

      # General availability based on the Account Switcher feature
      return true if account_switcher_helper.enabled? && account_switcher_helper.stashed_accounts.valid.any?

      # Prioritize showing the prompt if it's demanded by the app, but after we check for a skip
      return true if params[:prompt] == "select_account"

      # GitHub mobile for iOS/Android
      non_http_callback = !/\Ahttps?:\/\//.match?(application.callback_url)
      return true if non_http_callback

      return false
    end

    skip_account_picker = params[:skip_account_picker] == "true"
    return false if skip_account_picker

    non_http_callback = !/\Ahttps?:\/\//.match?(application.callback_url)
    return false unless non_http_callback

    # Setting a query parameter to verify to the request_access action that the user has picked an account
    requires_account_picker = params[:as_state].nil? || params[:as_state] != user_session.id.to_s
    requires_account_picker
  end

  def select_account_required_for_device_authorization?
    return false if params[:skip_account_picker] == "true"

    # General availability based on the Account Switcher feature
    account_switcher_helper.enabled?
  end

  def bad_update_request(reason)
    # There are currently 2 places users can switch accounts:
    # 1. Global Nav Panel
    # 2. Switch Account Page
    # If the user cannot successfully switch accounts from the global nav panel, we should redirect them back to the request page,
    # instead of the switch account page.
    from_global_nav = params[:from] == "nav_panel"
    error_redirect_path = from_global_nav ? params[:return_to] : list_accounts_path
    error_message = "Unable to switch to the selected account. Please try again. If the issue persists, try adding the account again."

    GitHub.dogstats.increment("account_switcher.switch_account", tags: [
      "result:failed",
      reason
    ])
    respond_to do |format|
      format.html do
        flash[:error] = error_message
        safe_redirect_to error_redirect_path
      end
      format.json { render json: { error: error_message }, status: :bad_request }
    end
  end
end
