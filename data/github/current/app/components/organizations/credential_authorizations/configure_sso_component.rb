# typed: strict
# frozen_string_literal: true

class Organizations::CredentialAuthorizations::ConfigureSsoComponent < ApplicationComponent
  extend T::Sig

  SSO_PAT_HELP_PATH = "/articles/authorizing-a-personal-access-token-for-use-with-a-saml-single-sign-on-organization/"
  SSO_KEY_HELP_PATH = "/articles/authorizing-an-ssh-key-for-use-with-a-saml-single-sign-on-organization/"

  KEYS_LABEL = "keys"
  TOKENS_LABEL = "tokens"

  sig { params(credential: T.any(OauthAccess, PublicKey), src: String).void }
  def initialize(credential:, src:)
    @credential = credential
    @src = src
  end

  sig { returns(String) }
  def id
    "credential-authorizations-for-#{@credential.id}"
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
  def sso_subjects_label
    case @credential
    when OauthAccess
      TOKENS_LABEL
    when PublicKey
      KEYS_LABEL
    else
      T.absurd(@credential)
    end
  end

  sig { returns(String) }
  def sso_help_url
    suffix =
      case @credential
      when OauthAccess
        SSO_PAT_HELP_PATH
      when PublicKey
        SSO_KEY_HELP_PATH
      end

    "#{GitHub.help_url}#{suffix}"
  end
end
