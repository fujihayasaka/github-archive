# typed: true
# frozen_string_literal: true

class Api::Authorizations < Api::App
  include ReceiveSchemaWithOpenApi
  FORBIDDEN_MESSAGE = "This API can only be accessed with username and " +
                      "password Basic Auth"

  # This API endpoint provides access to OAuth accesses. Due to backward
  # compatibility, the naming convention used in this API can be confusing.
  # Externally an OAuthAccess is called an "authorization" and an
  # OAuthAuthorization is called a "grant". The `/authorizations` endpoints
  # include the ability to list, get, create, update, and delete OAuth accesses
  # (authorizations) and the `/applications/grants` endpoints lets you list,
  # get, and delete their associated authorizations (grants).
  #
  # Because this endpoint deals with authentication credentials, it is only
  # accessible via basic authorization.
  before do
    @accepted_scopes = []
    set_forbidden_message(FORBIDDEN_MESSAGE, true)
    check_authorization { logged_in? && current_user.using_basic_auth? }
    populate_with_saml_context
  end

  # POST/PUT/PATCH requests should send an SMS for 2FA for the following routes:
  #
  # /authorizations
  # /authorizations/authorization_id
  # /authorizations/clients/client_id
  def route_sends_otp_sms?
    request.post? || request.put? || request.patch?
  end

  # List OAuth accesses
  #
  # Returns a list of OAuth accesses for the logged in user.
  get "/authorizations", operation_id: "oauth-authorizations/list-authorizations" do
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    scoped = current_user.oauth_accesses.preload(:application, :authorization)
    if key = params[:client_id].presence
      scoped = scoped.for_client_id(key)
      @authorization_application = OauthApplication.where(key: params[:client_id]).first || Integration.where(key: params[:client_id]).first
    end
    accesses = paginate_rel(scoped)

    deliver :oauth_access_hash, accesses
  end

  # Get a specific OAuth access
  #
  # Returns an OAuth access.
  get "/authorizations/:authorization_id", operation_id: "oauth-authorizations/get-authorization" do
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    access_id = int_id_param!(key: :authorization_id)
    if access = OauthAccessTokens.domain.by_user_and_id(current_user.id, access_id)
      populate_with_app_context(access.application)
      @authorization_application = access.application

      deliver :oauth_access_hash, access,
        last_modified: calc_last_modified_for_object(access)
    else
      deliver_error 404
    end
  end

  # Create an OAuth access
  #
  # Creates a new OAuth access tied to the OAuth application specified by
  # client_id and client_secret OR creates a personal token tied to an 'API'
  # oauth application (id = 0).
  post "/authorizations", operation_id: "oauth-authorizations/create-authorization" do
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    # Introducing strict validation of the authorization.create
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("authorization", "create", skip_validation: true)
    client_id     = data["client_id"].to_s
    client_secret = data["client_secret"].to_s

    app = OauthApplication.pseudo if client_id.empty? || client_secret.empty?
    app ||= find_oauth_app(client_id, client_secret)

    if app.nil?
      deliver_error! 422, message: "Invalid Application client_id or secret."
    end

    @authorization_application = app
    populate_with_app_context(app)

    if Apps::Privileged.capable?(:authorizations_via_rest_api_restricted, app: app)
      if Platform::Authorization::SAML.new(user: current_user).saml_organizations.any? # rubocop:todo GitHub/DoNotInstantiatePlatformObjects

        deliver_error!(410, message: "This action is no longer available via the API")
      end
    end

    response = OauthAccessTokens.domain.create(current_user.id, app, data)
    case response
    when GH::Result::Ok
      access, token = response.value
      deliver :oauth_access_hash, access, status: 201, token: token
    when GH::Result::Error::Unprocessable
      deliver_error 422, errors: response.items.first, documentation_url: @documentation_url
    when GH::Result::Error
      deliver_error! 422, message: response.message, documentation_url: @documentation_url
    end
  end

  # Create an OAuth access for a given application (and fingerprint if
  # provided)
  #
  # Finds the application by its id (and fingerprint if provided) and creates an
  # OAuth access for it. Returns the Oauth access.
  put "/authorizations/clients/:client_id", operation_id: "oauth-authorizations/get-or-create-authorization-for-app" do
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    data = receive_with_schema("authorization", "get-or-create-for-app")

    client_id     = params["client_id"].to_s
    client_secret = data["client_secret"].to_s

    app = find_oauth_app(client_id, client_secret)

    if app.nil?
      deliver_error! 422, message: "Invalid Application client_id or secret."
    end

    @authorization_application = app
    populate_with_app_context(app)

    fingerprint = data["fingerprint"]
    access = OauthAccessTokens.domain.by_user_app_and_fingerprint(current_user.id, app.id, app.class.name, fingerprint.present? ? fingerprint : nil)

    if access
      deliver :oauth_access_hash, access, status: 200
    else
      response = OauthAccessTokens.domain.create(current_user.id, app, data)
      case response
      when GH::Result::Ok
        access, token = response.value
        deliver :oauth_access_hash, access, status: 201, token: token
      when GH::Result::Error::Unprocessable
        deliver_error 422, errors: response.items.first, documentation_url: @documentation_url
      when GH::Result::Error
        deliver_error! 422, message: response.message, documentation_url: @documentation_url
      end
    end
  end

  # Create an OAuth access for a given application and fingerprint
  #
  # Finds the application by its id and fingerprint and creates an OAuth
  # access for it. Returns the OAuth access.
  put "/authorizations/clients/:client_id/:fingerprint", operation_id: "oauth-authorizations/get-or-create-authorization-for-app-and-fingerprint" do
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    # Introducing strict validation of the authorization.get-or-create-for-fingerprint
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    data = receive_with_schema("authorization", "get-or-create-for-fingerprint", skip_validation: true)
    client_id     = params["client_id"].to_s
    client_secret = data["client_secret"].to_s

    app = find_oauth_app(client_id, client_secret)

    if app.nil?
      deliver_error! 422, message: "Invalid Application client_id or secret."
    end

    @authorization_application = app
    populate_with_app_context(app)

    fingerprint = params["fingerprint"].to_s
    access = OauthAccessTokens.domain.by_user_app_and_fingerprint(current_user.id, app.id, app.class.name, fingerprint)

    if access
      deliver :oauth_access_hash, access, status: 200
    else
      data = data.merge("fingerprint" => fingerprint)

      response = OauthAccessTokens.domain.create(current_user.id, app, data)
      case response
      when GH::Result::Ok
        access, token = response.value
        deliver :oauth_access_hash, access, status: 201, token: token
      when GH::Result::Error::Unprocessable
        deliver_error 422, errors: response.items.first, documentation_url: @documentation_url
      when GH::Result::Error
        deliver_error! 422, message: response.message, documentation_url: @documentation_url
      end
    end
  end

  # Update an OAuth access
  #
  # Updates and returns an OAuth access.
  verbs :patch, :post, "/authorizations/:authorization_id", operation_id: "oauth-authorizations/update-authorization" do
    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    access_id = int_id_param!(key: :authorization_id)
    if access = OauthAccessTokens.domain.by_user_and_id(current_user.id, access_id)
      populate_with_app_context(access.application)
      @authorization_application = access.application

      # Introducing strict validation of the authorization.update
      # JSON schema would cause breaking changes for integrators
      # skip_validation until a rollout strategy can be determined
      # see: https://github.com/github/ecosystem-api/issues/1555
      data = receive_with_schema("authorization", "update", skip_validation: true)
      result = OauthAccessTokens.domain.update(access.id, current_user.id, data)

      case result
      when GH::Result::Ok
        deliver :oauth_access_hash, result.value
      when GH::Result::Error
        deliver_error 422,
          errors: result.message,
          documentation_url: "/rest/reference/oauth-authorizations#update-an-existing-authorization"
      end
    else
      deliver_error 404
    end
  end

  # Delete an OAuth access
  #
  # Destroys an OAuth access.
  delete "/authorizations/:authorization_id", operation_id: "oauth-authorizations/delete-authorization" do
    # Introducing strict validation of the authorization.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("authorization", "delete", skip_validation: true)

    # cap_bypass:to_fix was disabled because no resource is passed, ref https://github.com/github/authorization/issues/2183
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true # rubocop:disable GitHub/DoNotSkipCapAccessAllowed

    access_id = int_id_param!(key: :authorization_id)
    access = OauthAccessTokens.domain.by_user_and_id(current_user.id, access_id)

    if access
      populate_with_app_context(access.application)
      @authorization_application = access.application

      OauthAccessTokens.domain.destroy(access.id, :api_user, entry_point: :rest_api_authorizations_delete_authorization)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end

  private

  def find_oauth_app(client_id, client_secret)
    return nil if client_secret.blank?

    find_oauth_app_by_id_and_secret(client_id, client_secret) || find_integration_by_id_and_secret(client_id, client_secret)
  end

  def find_oauth_app_by_id_and_secret(client_id, client_secret)
    hash = OauthApplicationClientSecret.hash_for(client_secret)
    oauth_app_client_secret = OauthApplicationClientSecret.joins(:oauth_application).where(secret_hash: hash).where("oauth_applications.key" => client_id).first

    return unless oauth_app_client_secret
    return unless oauth_application = oauth_app_client_secret.oauth_application

    oauth_app_client_secret.access

    oauth_application
  end

  def find_integration_by_id_and_secret(client_id, client_secret)
    hash = IntegrationClientSecret.hash_for(client_secret)
    integration_client_secret = IntegrationClientSecret.joins(:integration).where(secret_hash: hash).where("integrations.key" => client_id).first

    return unless integration_client_secret
    return unless integration = integration_client_secret.integration

    integration_client_secret.access

    integration
  end

  def populate_with_app_context(app)
    case app
    when OauthApplication
      log_data[:oauth_application_id] = app.id
      GitHub.context.push(oauth_application_id: app.id)
    when Integration
      log_data[:integration_id] = app.id
      GitHub.context.push(integration_id: app.id)
    end
  end

  def populate_with_saml_context
    log_data[:saml_org_member] = Platform::Authorization::SAML.new(user: current_user).saml_organizations.any? # rubocop:todo GitHub/DoNotInstantiatePlatformObjects
  end
end
