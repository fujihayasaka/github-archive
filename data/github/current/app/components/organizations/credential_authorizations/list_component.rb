# typed: strict
# frozen_string_literal: true

class Organizations::CredentialAuthorizations::ListComponent < ApplicationComponent
  include AvatarHelper

  sig do
    params(
      credential: T.any(OauthAccess, PublicKey),
      org_credential_map: T::Hash[Organization, T.any(NilClass, Organization::CredentialAuthorization),
    ], experimental: T.nilable(String)).void
  end
  def initialize(credential:, org_credential_map:, experimental: nil)
    @credential = credential
    @org_credential_map = org_credential_map
    @experimental = experimental
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
  def cred_type
    case @credential
    when OauthAccess
      "Token"
    when PublicKey
      "Key"
    else
      T.absurd(@credential)
    end
  end

  sig { returns(String) }
  def id
    "credential-authorizations-for-#{@credential.id}"
  end

  sig { params(org: Organization).returns(String) }
  def authorize_path(org)
    target = org.external_identity_session_owner

    request_token = ::Organization::CredentialAuthorization.generate_request \
      organization: org, target: target, credential: @credential, actor: current_user

    case target
    when ::Organization
      org_idm_sso_path(target, authorization_request: request_token, return_to: return_to_path)
    when ::Business
      business_idm_sso_enterprise_path(target, authorization_request: request_token, return_to: return_to_path)
    else
      "#"
    end
  end

  sig { params(org: Organization).returns(String) }
  def destroy_path(org)
    case @credential
    when OauthAccess
      settings_user_token_authorization_path(@credential, org)
    when PublicKey
      public_key_authorization_path(@credential, org)
    else
      T.absurd(@credential)
    end
  end

  sig { params(org: Organization, user: User).returns(T.nilable(T::Boolean)) }
  def credential_disobeys_target_limit?(org, user)
    # This is a temporary bypass for the UI until we have a way to improve the peformance
    # See: https://github.com/github/ecosystem-apps/issues/6596
    return false if user.feature_enabled?(:bypass_cap_pats_policy_enforcement_ui)

    case @credential
    when OauthAccess
      !@credential.pat_adheres_by_targets_expiration_limit?(org) && !user_has_limit_exemption?(org, user)
    when PublicKey
      false
    else
      T.absurd(@credential)
    end
  end

  # Returns true if any orgs obey the expiration policy
  sig { returns(T::Boolean) }
  def has_available_orgs_to_authorize?
    @org_credential_map.any? { |org, _| !credential_disobeys_target_limit?(org, current_user) }
  end

  # Check if user is exempt from PAT expiration limits for the given org
  # Expiration is exempt via the business
  # Returns false if the org has no business
  # Returns true if the org's business has exempted admins and user is a business owner or billing manager
  sig { params(org: Organization, user: User).returns(T::Boolean) }
  def user_has_limit_exemption?(org, user)
    org.personal_access_token_classic_expiration_limit_exempted_for?(user)
  end

  sig { params(system_arguments: Primer::SystemArgumentsValue).returns(T.any(Primer::Alpha::SelectPanel::ItemList, Primer::Alpha::ActionList)) }
  def primer_panel_item_component(**system_arguments)
    component = Primer::Alpha::SelectPanel::ItemList
    component.new(**system_arguments)
  end
end
