# frozen_string_literal: true

module Authnd
  module Client
    # constants for the authenticate response attribute values
    # ex: (see https://thehub.github.com/epd/engineering/products-and-services/authentication/authnd/ruby-client)
    # resp = authenticator.Authenticate(context.Background(), ipAddr, req)
    # resp.Attributes["actor.type"] == client.ACTOR_TYPE_USER

    # actor.type values
    ACTOR_TYPE_USER = "User"
    ACTOR_TYPE_REPO = "Repo"

    # application.type values
    APPLICATION_TYPE_OAUTHAPPLICATION = "OAuthApplication"
    APPLICATION_TYPE_GITHUBAPPLICATION = "GithubApplication"

    # credential.type values
    CREDENTIAL_TYPE_LOGINPASSWORD = "LoginPassword"
    CREDENTIAL_TYPE_SSHPUBLICKEY = "SSHPublicKey"
    CREDENTIAL_TYPE_PERSONALACCESSTOKEN = "PersonalAccessToken"
    CREDENTIAL_TYPE_SIGNEDAUTHTOKEN = "SignedAuthToken"

    # Keep in sync with attributes in client/attributes.go
    module Attributes
      # universal attributes for actors
      ACTOR_ID = "actor.id"
      ACTOR_TYPE = "actor.type"
      USER_LOGIN = "user.login"
      USER_SPAMMY = "user.spammy"

      # universal attributes for credentials
      CREDENTIAL_ID = "credential.id"
      CREDENTIAL_PAYLOAD = "credential.payload"
      CREDENTIAL_SCOPES = "credential.scopes"
      CREDENTIAL_TYPE = "credential.type"
      CREDENTIAL_VERSION = "credential.version"
      CREDENTIAL_CREATED_AT = "credential.created_at_utc"
      CREDENTIAL_EXPIRES_AT = "credential.expires_at_utc"
      CREDENTIAL_ISSUED_AT = "credential.issued_at_utc"
      CREDENTIAL_ACCESSED_AT = "credential.accessed_at_utc"
      TOKEN_HASH = "token.hash"
      TOKEN_SUFFIX = "token.suffix"

      # oauth specific attributes
      PROGRAMMATIC_ACCESS_ID = "access.id"
      ORGANIZATION_SSO_AUTHORIZED_IDS = "organization.sso_authorized_ids"

      # public key specific attributes
      PUBLIC_KEY_NOT_VERIFIED = "publickey.notverified"

      # SAT specific attributes
      SESSION_ID = "session.id"

      # oauth app/u2s specific attributes
      APPLICATION_ID = "application.id"
      APPLICATION_TYPE = "application.type"
      APPLICATION_CLIENT_ID = "application.client_id"
      APPLICATION_NAME = "application.name"
      APPLICATION_OWNER_ID = "application.owner.id"
      APPLICATION_OWNER_TYPE = "application.owner.type"
      AUTHORIZATION_ID = "authorization.id"

      # github app specific attributes
      INSTALLATION_ID = "installation.id"
      INSTALLATION_TARGET_ID = "installation.target.id"
      INSTALLATION_TARGET_TYPE = "installation.target.type"
      SCOPED_INSTALLATION_TYPE = "scoped_installation.type"
      SCOPED_INSTALLATION_ID = "scoped_installation.id"
      SCOPED_INSTALLATION_REPOSITORY_ID = "scoped_installation.repository_id"

      # IET specific attributes
      DELEGATED_CLAIMS = "delegated_claims"

      # rate limit related attributes
      # used with both oauth and github apps
      RATE_LIMIT_OVERRIDE = "rate_limit.override"
      TEMPORARY_RATE_LIMIT = "rate_limit.temporary"
      TEMPORARY_RATE_LIMIT_EXPIRES_AT = "rate_limit.temporary.expires_at"
      DYNAMIC_RATE_LIMIT = "rate_limit.dynamic" # only applies to GitHub apps

      # Gateway attributes related to "request owner" for GitHub/OAuth apps
      GATEWAY_REQUEST_OWNER_ID = "gateway.request_owner.id"
      GATEWAY_REQUEST_OWNER_HIGHER_LIMIT = "gateway.request_owner.higher_limit"
    end
  end
end
