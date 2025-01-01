# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module ProgrammaticAccessToken
  TOKEN_PREFIXES = /(gh1_|github_pat_)/
  USER_PATTERN = /\A#{TOKEN_PREFIXES}/

  def self.credential_type
    ::ProgrammaticAccessToken::Finder::TOKEN_TYPE
  end

  def self.name_max_length
    ::UserProgrammaticAccess::NAME_MAX_LENGTH
  end

  def self.description_max_length
    ::UserProgrammaticAccess::DESCRIPTION_MAX_LENGTH
  end

  # Public: Generate an API token for the given *ProgrammaticAccess.
  #
  # Returns a ProgrammaticAccessToken::Result.
  def self.generate(access, opts = {})
    ::ProgrammaticAccessToken::Creator.perform(access, opts)
  end

  # Public: Hash a token for logging purposes
  #
  # Returns a String.
  def self.hash_token(token)
    Digest::SHA256.base64digest(token)
  end

  # Public: Regenerate a token by revoking the current and creating
  # a new one with the expiration options
  #
  # Returns a ProgrammaticAccessToken::Result.
  def self.regenerate(access, opts = {})
    ::ProgrammaticAccessToken::Regenerator.perform(access, opts)
  end

  def self.expiration_for(access)
    ::ProgrammaticAccessToken::ExpirationReader.perform(access)
  end

  # Public: Get the last eight characters of the raw token
  #
  # Note: May eventually want to reduce calls to Authnd by
  # combining all attribute results within one call and not
  # using Finder in each one.
  #
  # Returns a string
  def self.token_last_eight(access)
    token_result = ::ProgrammaticAccessToken::Finder.perform(access)
    token_result.success? ? token_result.value.first&.token_last_eight : ""
  end
end
