# typed: strict
# frozen_string_literal: true

class Organizations::CredentialAuthorizations::ItemComponent < ApplicationComponent
  extend T::Sig

  sig do
    params(
      org: Organization,
      credential: T.any(OauthAccess, PublicKey),
      credential_authorization: T.any(NilClass, Organization::CredentialAuthorization),
      sso_availability: T.nilable(String)
    ).void
  end
  def initialize(org, credential, credential_authorization, sso_availability = nil)
    @org = org
    @credential = credential
    @credential_authorization = credential_authorization
    @sso_availability = sso_availability
  end

  sig { returns(String) }
  def cred_title
    case @credential
    when OauthAccess
      @credential.description
    when PublicKey
      @credential.title
    else
      T.absurd(@credential)
    end
  end

  sig { returns(String) }
  def authorize_path
    target = @org.external_identity_session_owner

    request_token = ::Organization::CredentialAuthorization.generate_request \
      organization: @org, target: target, credential: @credential, actor: current_user

    case target
    when ::Organization
      org_idm_sso_path(target, authorization_request: request_token, return_to: return_to_path)
    when ::Business
      business_idm_sso_enterprise_path(target, authorization_request: request_token, return_to: return_to_path)
    else
      "#"
    end
  end

  sig { returns(String) }
  def destroy_path
    case @credential
    when OauthAccess
      settings_user_token_authorization_path(@credential, @org)
    when PublicKey
      public_key_authorization_path(@credential, @org)
    else
      T.absurd(@credential)
    end
  end
end
