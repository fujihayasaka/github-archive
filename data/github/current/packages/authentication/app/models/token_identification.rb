# typed: strict
# frozen_string_literal: true

module TokenIdentification
  PAT_REGEX = /\Aghp_[A-Za-z0-9]{36}\z/
  FG_PAT_REGEX = /\A(gh1_[A-Za-z0-9]{21}_[A-Za-z0-9]{59}|github_pat_[0-9][A-Za-z0-9]{21}_[A-Za-z0-9]{59})\z/
  OAUTH_APP_TOKEN_REGEX = /\Agho_[A-Za-z0-9]{36}\z/
  GH_APP_U2S_TOKEN_REGEX = /\Aghu_[A-Za-z0-9]{36}\z/
  # New format allows dots and underscores, variable length (min 36 chars after prefix).
  # https://github.blog/changelog/2026-05-15-github-app-installation-tokens-per-request-override-header/
  GH_APP_S2S_TOKEN_REGEX = /\Aghs_[A-Za-z0-9._-]{36,}\z/
  GH_APP_REFRESH_TOKEN_REGEX = /\Aghr_[A-Za-z0-9]{76}\z/

  # Public: Identifies the type of tokens in the list of tokens
  #
  # tokens - The list of tokens to identify
  #
  # Returns a hash of token types
  sig { params(tokens: T::Array[String]).returns(T::Hash[Symbol, T::Array[String]]) }
  def self.identify_tokens(tokens)
    return {} if tokens.empty?

    token_identifier_hash = {
      TokenRevocation::Helper::PAT_CREDENTIAL => [],
      TokenRevocation::Helper::FG_PAT_CREDENTIAL => [],
      TokenRevocation::Helper::OAUTH_APP_TOKEN_CREDENTIAL => [],
      TokenRevocation::Helper::GH_APP_U2S_CREDENTIAL => [],
      TokenRevocation::Helper::GH_APP_S2S_CREDENTIAL => [],
      TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL => [],
    }
    unknown_tokens = []

    # Strip whitespace and remove dupes in the tokens array
    uniq_tokens = Set.new(tokens.map(&:strip))

    # Iterate through the tokens, identify the token type,
    # and add the token to the appropriate array in the hash
    uniq_tokens.each do |token|
      token_type = identify_token(token)
      if token_type.nil?
        unknown_tokens << token
        next
      end
      token_identifier_hash[token_type] << token
    end

    token_identifier_hash[:UNKNOWN] = unknown_tokens

    token_identifier_hash
  end

  # Public: Determines the type of token
  #
  # token - The token to identify
  #
  # Returns a type of token, or nil if the token is not recognized
  sig { params(token: String).returns(T.nilable(Symbol)) }
  def self.identify_token(token)
    if is_pat_credential?(token)
      TokenRevocation::Helper::PAT_CREDENTIAL
    elsif is_fg_pat_credential?(token)
      TokenRevocation::Helper::FG_PAT_CREDENTIAL
    elsif TokenRevocation::Helper.credential_revocation_oauth_app_tokens_enabled? && is_oauth_app_token_credential?(token)
      TokenRevocation::Helper::OAUTH_APP_TOKEN_CREDENTIAL
    elsif TokenRevocation::Helper.credential_revocation_u2s_tokens_enabled? && is_u2s_credential?(token)
      TokenRevocation::Helper::GH_APP_U2S_CREDENTIAL
    elsif TokenRevocation::Helper.credential_revocation_s2s_tokens_enabled? && is_s2s_credential?(token)
      TokenRevocation::Helper::GH_APP_S2S_CREDENTIAL
    elsif TokenRevocation::Helper.credential_revocation_refresh_tokens_enabled? && is_refresh_token_credential?(token)
      TokenRevocation::Helper::GH_APP_REFRESH_TOKEN_CREDENTIAL
    else
      nil
    end
  end

  # Public: Determines if a token is a PAT
  #
  # token - The token to check
  #
  # Returns a boolean, true if the token is a PAT, false otherwise
  sig { params(token: String).returns(T::Boolean) }
  def self.is_pat_credential?(token)
    PAT_REGEX.match?(token)
  end

  # Public: Determines if a token is a fine grained PAT
  #
  # token - The token to check
  #
  # Returns a boolean, true if the token is a fine grained PAT, false otherwise
  sig { params(token: String).returns(T::Boolean) }
  def self.is_fg_pat_credential?(token)
    FG_PAT_REGEX.match?(token)
  end

  # Public: Determines if a token is an OAuth token
  #
  # token - The token to check
  #
  # Returns a boolean, true if the token is an OAuth token, false otherwise
  sig { params(token: String).returns(T::Boolean) }
  def self.is_oauth_app_token_credential?(token)
    OAUTH_APP_TOKEN_REGEX.match?(token)
  end

  # Public: Determines if a token is a user-to-server token
  #
  # token - The token to check
  #
  # Returns a boolean, true if the token is a user-to-server token, false otherwise
  sig { params(token: String).returns(T::Boolean) }
  def self.is_u2s_credential?(token)
    GH_APP_U2S_TOKEN_REGEX.match?(token)
  end

  # Public: Determines if a token is a server-to-server token
  #
  # token - The token to check
  #
  # Returns a boolean, true if the token is a server-to-server token, false otherwise
  sig { params(token: String).returns(T::Boolean) }
  def self.is_s2s_credential?(token)
    GH_APP_S2S_TOKEN_REGEX.match?(token)
  end

  # Public: Determines if a token is a GitHub App refresh token
  #
  # token - The token to check
  #
  # Returns a boolean, true if the token is a GitHub App refresh token, false otherwise
  sig { params(token: String).returns(T::Boolean) }
  def self.is_refresh_token_credential?(token)
    GH_APP_REFRESH_TOKEN_REGEX.match?(token)
  end
end
