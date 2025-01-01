# typed: true
# frozen_string_literal: true

class Api::Applications < Api::App
  before do
    @accepted_scopes = []
  end

  # This API endpoint provides access for applications to check tokens without
  # hitting the rate limit for failed login attempts. Because this
  # endpoint deals with OAuth tokens themselves, it is only accessible via
  # Basic Authentication using application credentials.
  #
  # By overriding #attempt_login, we disable login via Basic Auth using
  # *user* credentials, and we enable login via Basic Auth using OAuth
  # application credentials.
  def attempt_login
    @current_user = nil
    deliver_error!(404) unless request_credentials.login_password_present?

    reject_for_bad_credentials! unless current_app
  end

  # Public: Determines whether the request is sufficiently authenticated to
  # access the API when running in Private Mode (i.e., if the request is
  # authenticated as an OAuth app).
  #
  # Returns true if the request is authenticated; false otherwise.
  def authenticated_for_private_mode?
    current_app
  end

  # [Removed] Check a token using application credentials
  # rubocop:todo GitHub/ControlAccess
  get "/applications/:client_id/tokens/:access_token", operation_id: "apps/check-authorization" do
    # We keep the endpoint definition to prevent accidental logging of access tokens.
    deliver_error!(404)
  end
  # rubocop:enable GitHub/ControlAccess

  # [New] Check a token using application credentials
  post "/applications/:client_id/token", operation_id: "apps/check-token" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    data = receive_with_schema("authorization", "check-token")
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    token = data["access_token"]
    ensure_oauth_creds_match_request!
    access = find_token_for_oauth_app_from_body(data)
    deliver :oauth_access_hash, access, user: true, token: token
  end

  # Delete all app tokens using application credentials
  delete "/applications/:client_id/tokens", operation_id: :deprecated do
    @route_owner = "@github/ecosystem-apps"
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    ensure_oauth_creds_match_request!
    deliver_error!(403, message: "Forbidden") if token_revocation_forbidden?
    deliver_error!(410, message: "Gone via the API. You can still revoke all tokens via the settings page for this application.")
  end

  # [Removed] Reset OauthAccess#token using application credentials
  # rubocop:todo GitHub/ControlAccess
  post "/applications/:client_id/tokens/:access_token", operation_id: "apps/reset-authorization" do
    # We keep the endpoint definition to prevent accidental logging of access tokens.
    deliver_error!(404)
  end
  # rubocop:enable GitHub/ControlAccess

  # [New] Reset OauthAccess#token using application credentials
  patch "/applications/:client_id/token", operation_id: "apps/reset-token" do # rubocop:disable GitHub/DuplicateRoutesAreDefinedTogether
    data = receive_with_schema("authorization", "reset-token")

    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    ensure_oauth_creds_match_request!
    access = find_token_for_oauth_app_from_body(data)

    # Older tokens will have a code set that is not needed.
    access.code = nil
    deliver :oauth_access_hash, access, user: true, token: access.reset_token
  end

  # [Removed] Delete an app token using application credentials
  # rubocop:todo GitHub/ControlAccess
  delete "/applications/:client_id/tokens/:access_token", operation_id: "apps/revoke-authorization-for-application" do
    # We keep the endpoint definition to prevent accidental logging of access tokens.
    deliver_error!(404)
  end
  # rubocop:enable GitHub/ControlAccess

  # [New] Delete an app token using application credentials
  delete "/applications/:client_id/token", operation_id: "apps/delete-token" do
    # TODO: update docs ref
    data = receive_with_schema("authorization", "revoke-token")
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    ensure_oauth_creds_match_request!
    access = find_token_for_oauth_app_from_body(data)
    access.destroy_with_explanation(:oauth_application, entry_point: :rest_api_applications_delete_oauth_access_token)
    deliver_empty status: 204
  end

  # [Removed] Delete an app authorization using application credentials
  # rubocop:todo GitHub/ControlAccess
  delete "/applications/:client_id/grants/:access_token", operation_id: "apps/revoke-grant-for-application" do
    # We keep the endpoint definition to prevent accidental logging of access tokens.
    deliver_error!(404)
  end
  # rubocop:enable GitHub/ControlAccess

  # [New] Delete an app authorization using application credentials
  delete "/applications/:client_id/grant", operation_id: "apps/delete-authorization" do
    # TODO: update docs ref
    data = receive_with_schema("application-grant", "delete-for-app-token")

    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    ensure_oauth_creds_match_request!
    authorization = find_token_for_oauth_app_from_body(data).authorization
    authorization.destroy_with_explanation(:oauth_application, entry_point: :rest_api_applications_delete_oauth_authorization)
    deliver_empty status: 204
  end

  post "/applications/:client_id/token/scoped", operation_id: "apps/scope-token" do
    data = receive_with_schema("authorization", "scope-token")

    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    unless current_app.is_a?(Integration)
      deliver_error!(422, message: "This endpoint is only available for GitHub Apps")
    end

    ensure_oauth_creds_match_request!
    access = find_token_for_oauth_app_from_body(data)

    target = if data.key?("target_id")
      User.find_by(id: data["target_id"])
    else
      User.find_by(login: data["target"])
    end

    record_or_404(target)

    repository_ids = if data.key?("repository_ids")
      data["repository_ids"]
    elsif data.key?("repositories")
      T.must(target).repositories.where(name: data["repositories"]).pluck(:id)
    end

    new_access, error = current_app.grant_scoped_access_from(
      access,
      target,
      permissions: data["permissions"],
      resources: { repository_ids: repository_ids },
      entry_point: :rest_api_create_scoped_user_to_server_token
    )

    if error
      case error[:error]
      when :invalid_token
        deliver_error!(401, message: error[:error_description])
      when :token_creation_failure
        deliver_error!(500, message: error[:error_description])
      else
        deliver_error!(403, message: error[:error_description])
      end
    end

    token, _ = new_access.redeem
    installation = new_access.installation

    deliver :oauth_access_hash, new_access, user: true, token: token, installation: installation
  end

  private

  # Internal: Overrides the default behavior for finding the current app. Finds
  # the OauthApplication/Integration (if any) associated with the current request based
  # on the client ID and client secret provided via Basic Auth.
  #
  # Returns an OauthApplication/Integration or nil.
  def find_current_app
    if (oauth_app = current_app_via_authorization_header)
      oauth_app
    elsif (github_app = current_integration_via_authorization_header)
      github_app
    end
  end

  def oauth_creds_match_request?
    return false unless current_app

    SecurityUtils.secure_compare(params[:client_id], current_app.key)
  end

  # See https://github.com/github/github/issues/33359
  # We're temporarily disabling token revocation for our
  # own apps until we can deprecate the entire endpoint.
  def token_revocation_forbidden?
    current_app && current_app.github_owned?
  end

  def find_token_for_oauth_app_from_params
    find_access_token(params[:access_token])
  end

  def find_token_for_oauth_app_from_body(body)
    find_access_token(body["access_token"])
  end

  def find_access_token(token)
    if (access = current_app.accesses.with_active_token(token))
      return access if access.user&.can_authenticate_via_oauth?
    end

    deliver_error!(404)
  end

  def ensure_oauth_creds_match_request!
    deliver_error!(404) unless oauth_creds_match_request?
  end
end
