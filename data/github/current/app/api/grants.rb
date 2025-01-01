# typed: true
# frozen_string_literal: true

class Api::Grants < Api::App
  include ReceiveSchemaWithOpenApi
  FORBIDDEN_MESSAGE = "This API can only be accessed with username and " +
                      "password Basic Auth"

  # This API endpoint provides access to OAuth authorizations. Due to backward
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
    check_authorization do logged_in? && !current_user.using_oauth? &&
      current_user.can_authenticate_via_username_password_basic_auth?
    end
  end

  # List OAuth authorizations
  #
  # Returns a list of OAuth authorizations for the logged in user.
  get "/applications/grants", operation_id: "oauth-authorizations/list-grants" do
    control_access :apps_audited, resource: Platform::PublicResource.new, allow_integrations: false, allow_user_via_granular_actor: false # rubocop:disable GitHub/PublicResource

    scoped = current_user.oauth_authorizations.third_party
    if key = params[:client_id].presence
      scoped = scoped.for_client_id(key)
      @grant_application = OauthApplication.where(key: params[:client_id]).first || Integration.where(key: params[:client_id]).first
    end

    authorizations = paginate_rel(scoped)

    GitHub::PrefillAssociations.prefill_associations(authorizations, :application)

    deliver :oauth_authorization_hash, authorizations
  end

  # Get a specific OAuth authorization
  #
  # Returns an OAuth authorization.
  get "/applications/grants/:grant_id", operation_id: "oauth-authorizations/get-grant" do
    # cap_bypass: could be updated to use Platform::PublicResource.new
    # rubocop:todo GitHub/DoNotSkipCapAccessAllowed
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true

    if authorization = current_user.oauth_authorizations.third_party.find_by_id(int_id_param!(key: :grant_id))
      @grant_application = authorization.application
      deliver :oauth_authorization_hash, authorization,
        last_modified: calc_last_modified_for_object(authorization)
    else
      deliver_error 404
    end
  end

  # Delete an OAuth authorization
  #
  # Destroys an OAuth authorization.
  delete "/applications/grants/:grant_id", operation_id: "oauth-authorizations/delete-grant" do
    # Introducing strict validation of the application-grant.delete
    # JSON schema would cause breaking changes for integrators
    # skip_validation until a rollout strategy can be determined
    # see: https://github.com/github/ecosystem-api/issues/1555
    receive_with_schema("application-grant", "delete", skip_validation: true)

    # cap_bypass: could be updated to use Platform::PublicResource.new
    # rubocop:todo GitHub/DoNotSkipCapAccessAllowed
    control_access :apps_audited, allow_integrations: false, allow_user_via_granular_actor: false, disable_conditional_access_policies: true

    if authorization = current_user.oauth_authorizations.third_party.find_by_id(int_id_param!(key: :grant_id))
      @grant_application = authorization.application
      authorization.destroy_with_explanation(:api_user, entry_point: :rest_api_grants_delete_grant)
      deliver_empty(status: 204)
    else
      deliver_error 404
    end
  end
end
