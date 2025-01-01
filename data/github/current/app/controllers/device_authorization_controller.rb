# typed: true
# frozen_string_literal: true

class DeviceAuthorizationController < ApplicationController
  include ControllerMethods::Oauth
  include OauthHelper

  before_action :authorization_required

  before_action :verify_user_code,                 only: [:request_access]
  before_action :find_device_authorization_grant!, only: [:authorize]
  before_action :set_scopes,                       only: [:request_access, :authorize]

  before_action :check_eligibility,                         only: [:request_access, :authorize]
  before_action :conditional_sudo_filter,                   only: [:authorize]
  before_action :reject_dangerous_requests,                 only: [:request_access, :authorize]
  before_action :reject_suspended_applications,             only: [:request_access, :authorize]
  before_action :reject_attribution_only_system_identities, only: [:request_access, :authorize]

  before_action :reject_applications_owned_by_spammy, only: [:request_access, :authorize]
  before_action :reject_inaccessible_internal_apps, only: [:request_access, :authorize]

  # Deliberately opt out of conditional access policies and handle enforcement inline.
  # For example see DeviceAuthorizationController#request_access -> `if show_sso_selection?`
  # cap_bypass: needs closer look need to review protected resource protections
  skip_before_action :perform_conditional_access_checks # rubocop:todo GitHub/DoNotSkipCapBeforeAction

  layout "layouts/device_authorization"
  javascript_bundle :oauth
  stylesheet_bundle :oauth
  javascript_bundle :"user-code-prompt"

  include GitHub::RateLimitedRequest
  rate_limit_requests \
    only: [:request_access, :authorize],
    if: :logged_in?,
    max: 50,
    ttl: 1.hour,
    key: :absolute_authorize_rate_limit_key,
    log_key: "device-authorization"

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:failure]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:success]

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql5,
    only: [:user_code_prompt]

  def user_code_prompt # rubocop:todo GitHub/UseRestfulActions
    return redirect_to device_authorization_select_account_path if account_picker_required?
    render "device_authorization/user_code_prompt"
  end

  def request_access # rubocop:todo GitHub/UseRestfulActions
    if show_sso_selection?(application)
      cap_unauthorized_saml_orgs = unauthorized_saml_organizations_for_application
      more_than_one_target = (cap_unauthorized_saml_orgs.size > 1)
      GitHub.dogstats.increment("device_authorization.sso.required", tags: ["multiple_targets:#{more_than_one_target}"])

      cap_unauthorized_saml_orgs.each do |org|
        allow_external_redirect_after_post(provider: org.saml_provider)
      end

      cap_authorized_saml_organizations = cap_filter.satisfied_resources(current_user&.organizations, only: :saml)

      render "device_authorization/identity_management/sso", layout: "layouts/session_authentication", locals: {
        application:                          application,
        cap_authorized_saml_organizations:    cap_authorized_saml_organizations,
        form_data:                            captured_form_data_via_enforcement,
        return_to_url:                        request.url,
        cap_unauthorized_saml_organizations:  cap_unauthorized_saml_orgs,
        user_code:                            @device_authorization.user_code,
      }

      return
    end

    @authorization = current_user.oauth_authorizations.find_by(application: application)

    options = {
      authorization: @authorization,
      application: application,
      form_submission_path: device_authorize_path,
      params: { user_code: @device_authorization.user_code },
      scopes: @scopes,
      session: session,
      rate_limited: false,
      include_device_warning: true,
      device_authorization: @device_authorization,
    }

    case application
    when Integration
      options[:events]      = application.default_permissions
      options[:permissions] = application.default_permissions

      view_model = create_view_model(Oauth::AuthorizeIntegrationView, options)
      render "oauth/authorize_integration", layout: "layouts/oauth_authorization", locals: { view: view_model }
    else
      options[:unauthorized_saml_organizations] = unauthorized_saml_organizations_for_application
      options[:unauthorized_ip_allowlist_organization_ids] = cap_filter.unauthorized_resource_ids(current_user&.organizations, only: [:ip_allowlist, :external_conditional_access_policy])

      view_model = create_view_model(Oauth::AuthorizeView, options)
      render "oauth/authorize", layout: "layouts/oauth_authorization", locals: { view: view_model }
    end
  end

  def authorize # rubocop:todo GitHub/UseRestfulActions
    if oauth_access_authorized?
      options = {
        scope: @scopes,
        integration_version_number: params[:integration_version_number],
        user_session: user_session,
        entry_point: :device_authorization_controller_authorize,
      }

      @access = application.grant(current_user, options)
      @device_authorization.update!(oauth_access: @access, user_code: nil)

      instrument_integration_listing

      log_data[:verification_code] = secret_last_eight(@access.code)
      redirect_to device_success_path
    else
      GitHub.dogstats.increment("device_authorization.conversion", tags: ["error:access_denied"])
      @device_authorization.update(access_denied: true, user_code: nil)

      flash[:notice] = "You have denied #{application.name} access"
      redirect_to dashboard_path
    end
  end

  def success # rubocop:todo GitHub/UseRestfulActions
    render "device_authorization/success"
  end

  def failure # rubocop:todo GitHub/UseRestfulActions
    render "device_authorization/failure"
  end

  private

  def account_picker_required?
    return false if params[:skip_account_picker] == "true"

    # General availability based on the Account Switcher feature
    account_switcher_helper.enabled?
  end

  # Regardless of permissiveness, provide an absolute limit to the number of
  # authorize requests within a reasonable timeframe.
  def absolute_authorize_rate_limit_key
    "device-authorization-abs:authorize:#{current_user.id}:#{client_id}"
  end

  memoize def client_id
    application.key
  end

  def find_device_authorization_grant!
    @device_authorization = DeviceAuthorizationGrant.unclaimed.find_by!(user_code: submitted_user_code)
  end

  def reject_suspended_applications
    return unless application.suspended?

    reason = application.is_a?(Integration) ? :github_app_suspended : :oauth_application_suspended
    redirect_to device_failure_path(reason: reason)
  end

  def reject_applications_owned_by_spammy
    redirect_to device_failure_path(reason: :spammy_application) if application&.spammy?
  end

  # Internal visibility GitHub Apps are only authorizable by a member of the owning
  # enterprise.
  def reject_inaccessible_internal_apps
    return unless application.is_a?(Integration) && application.internal_visibility?

    if enterprise = application&.owner
      redirect_to device_failure_path(reason: :not_found) unless enterprise.async_member?(current_user).sync
    end
  end

  memoize def application
    application = @device_authorization.application

    case application
    when Integration
      log_data[:integration_id] = application.id
    when OauthApplication
      log_data[:oauth_application_id] = application.id
    end

    application
  end

  def access_denied # rubocop:todo GitHub/UseRestfulActions
    if action_name == "user_code_prompt" && params[:provider].present? && FeatureFlag.vexi.enabled?(:social_signup, default: false)
      return redirect_to social_initiate_path(provider: params[:provider], return_to: request.url)
    end
    # otherwise defer to the default authenticated_system behavior
    super
  end

  def set_scopes
    @scopes = @device_authorization.scopes || []
  end

  def submitted_user_code # rubocop:todo GitHub/ControllersShouldUseMemoizeForMemoization
    return @submitted_user_code if defined?(@submitted_user_code)

    # params[:user_code] is provided by the submit button
    # when the user authorizes the app.
    @submitted_user_code = params[:user_code]
    return @submitted_user_code unless @submitted_user_code.nil?

    # The user_code is broken up into parts when the user is submitting
    # the code for the first `GET /login/device`
    @submitted_user_code = 9.times.map { |index| params[:"user-code-#{index}"] }
    @submitted_user_code = @submitted_user_code.join("").upcase
  end

  def verify_user_code
    device_authorization = DeviceAuthorizationGrant.find_by(user_code: submitted_user_code)

    case
    when device_authorization.nil?
      redirect_to device_failure_path(reason: :not_found)
    when device_authorization.access_denied?
      redirect_to device_failure_path(reason: :not_found)
    when device_authorization.expired?
      redirect_to device_failure_path(reason: :expired)
    when device_authorization.claimed?
      if device_authorization.user == current_user
        redirect_to device_success_path
      else
        redirect_to device_failure_path(reason: :not_found)
      end
    else
      @device_authorization = device_authorization
    end
  end
end
