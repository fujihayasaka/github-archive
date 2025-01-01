# typed: true
# frozen_string_literal: true

class Api::OrganizationsCredentialAuthorizations < Api::App
  include ReceiveSchemaWithOpenApi

  # GET a list of authorized credentials for an org
  get "/organizations/:organization_id/credential-authorizations", operation_id: "orgs/list-saml-sso-authorizations" do
    @accepted_scopes = %w(read:org)

    org = find_org!

    control_access :authorized_org_credentials_reader,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    credentials_rel = if params[:login].present?
      credentials_query = Organization::CredentialAuthorization
        .by_organization(organization: org)
        .active

      if actor = User.find_by_login(params[:login])
        if org.feature_enabled?(:org_credential_authorizations_api_all_oauth_tokens) || org.business&.feature_enabled?(:org_credential_authorizations_api_all_oauth_tokens)
          credentials_query = credentials_query
            .by_actor(actor: actor)
            .includes(:actor, :credential, :organization)
            .order(:id)
        else
          personal_token_ids = OauthAccess.where(user_id: actor.id).personal_tokens.ids
          credentials_query = credentials_query
            .by_actor(actor: actor)
            .where("credential_id IN (?) OR credential_type <> 'OauthAccess'", personal_token_ids)
            .includes(:actor, :credential, :organization)
            .order(:id)
        end
      else
        credentials_query = credentials_query.none
      end

      credentials_query
    else
      credentials_query = Organization::CredentialAuthorization
        .by_organization(organization: org)
        .active
        .includes(:actor, :credential, :organization)
        .order(:id)

      if org.feature_enabled?(:org_credential_authorizations_api_all_oauth_tokens) || org.business&.feature_enabled?(:org_credential_authorizations_api_all_oauth_tokens)
        credentials_query = credentials_query
      else
        credentials_query = credentials_query.excluding_applications
      end

      credentials_query
    end

    credential_auths = paginate_rel(credentials_rel)

    deliver :credential_authorizations_hash, credential_auths, current_user: current_user
  end

  # revoke authorized access of a credential from an org
  delete "/organizations/:organization_id/credential-authorizations/:credential_auth_id", operation_id: "orgs/remove-saml-sso-authorization" do
    @accepted_scopes   = %w(admin:org)

    receive_with_schema("credential-authorization", "delete", skip_validation: true)

    org = find_org!

    authorized_credential = Organization::CredentialAuthorization.where(id: params[:credential_auth_id]).first

    deliver_error! 404 unless authorized_credential.present?

    control_access :authorized_org_credentials_writer,
      resource: org,
      organization: org,
      allow_integrations: true,
      allow_user_via_granular_actor: true

    Organization::CredentialAuthorization.revoke(
      organization: org,
      credential: authorized_credential.credential,
      actor: current_user,
    )

    deliver_empty status: 204
  end
end
