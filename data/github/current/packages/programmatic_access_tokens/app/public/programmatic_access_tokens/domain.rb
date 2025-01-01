# typed: strict
# frozen_string_literal: true

module ProgrammaticAccessTokens
  class Domain < GH::Domain::Base
    TOKEN_PREFIXES = /(gh1_|github_pat_)/
    USER_PATTERN = /\A#{TOKEN_PREFIXES}/

    # Checks if the given token matches the ProgrammaticAccessTokens pattern
    #
    # token - The string to check
    #
    # Returns true if token follows the AuthenticationToken pattern,
    #   false if it doesn't
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def self.matches_pattern?(token)
      !!(token =~ USER_PATTERN)
    end

    # Returns the string representation of the credential type.
    sig { returns(String) }
    def self.credential_type
      ::ProgrammaticAccessToken::Finder::TOKEN_TYPE
    end

    # Returns an IResult failure object for error handling.
    sig { params(message: String).returns(IResult).checked(:always).on_failure(:raise) }
    def self.failure(message)
      ::ProgrammaticAccessToken::Result.failed(message)
    end

    # Generates a programmatic access token with the specified access and options.
    #
    # Please do not use this method directly and use ProgrammaticAccessWithGrantAndToken::Creator.perform instead. If you need to directly call this method,
    # please reach out to #authentication.
    sig { params(actor_id: Integer, access_id: Integer, opts: T::Hash[Symbol, T.untyped]).returns(IResult).checked(:always).on_failure(:raise) }
    def generate(actor_id, access_id, opts = {})
      ::ProgrammaticAccessToken::Creator.perform(actor_id, access_id, opts)
    end

    # Regenerates a programmatic access token with the specified access and options.
    #
    # Please do not use this method directly and use ProgrammaticAccess::TokenManager.regenerate instead. If you need to directly call this method,
    # please reach out to #authentication.
    sig { params(actor_id: Integer, access_id: Integer, opts: T::Hash[Symbol, T.untyped]).returns(IResult).checked(:always).on_failure(:raise) }
    def regenerate(actor_id, access_id, opts = {})
      ::ProgrammaticAccessToken::Regenerator.perform(actor_id, access_id, opts)
    end

    # Returns the expiration time for the specified access.
    #
    # Please do not use this method directly and use ProgrammaticAccess::TokenManager.expiration_for instead. If you need to directly call this method,
    # please reach out to #authentication.
    sig { params(actor_id: Integer, access_id: Integer, opts: T::Hash[Symbol, T.untyped]).returns(IResult).checked(:always).on_failure(:raise) }
    def expiration_for(actor_id, access_id, opts = {})
      ::ProgrammaticAccessToken::ExpirationReader.perform(actor_id, access_id, opts)
    end

    # Returns the last eight characters of the token for the specified access.
    #
    # Please do not use this method directly and use ProgrammaticAccess::TokenManager.token_last_eight instead. If you need to directly call this method,
    # please reach out to #authentication.
    sig { params(actor_id: Integer, access_id: Integer, opts: T::Hash[Symbol, T.untyped]).returns(String) }
    def token_last_eight(actor_id, access_id, opts = {})
      token_result = ::ProgrammaticAccessToken::Finder.perform(actor_id, access_id, opts)
      token_result.success? ? token_result.value.first&.token_last_eight : ""
    end

    # Destroys a programmatic access token
    #
    # Please do not use this method directly and use ProgrammaticAccess.destroy instead. If you need to directly call this method,
    # please reach out to #authentication.
    sig { params(actor_id: Integer, access_id: Integer, opts: T::Hash[Symbol, T.untyped]).returns(IResult).checked(:always).on_failure(:raise) }
    def destroy(actor_id, access_id, opts = {})
      ::ProgrammaticAccessToken::Destroyer.perform(actor_id, access_id, opts)
    end

    # Returns the hashed version of the given token.
    sig { params(token: String).returns(String) }
    def hash_token(token)
      Digest::SHA256.base64digest(token)
    end

    # Verifies a programmatic access token (using authnd's credential manager service - this is used by secret scanning)
    sig { params(tokens: T::Array[String]).returns(IResult).checked(:always).on_failure(:raise) }
    def verify(tokens)
      ::ProgrammaticAccessToken::Verifier.perform(tokens)
    end

    # Authenticates a programmatic access token (using authnd's authenticate API)
    #
    # This method should be used when you know that the access token is a ProgrammaticAccessToken,
    # but there is no difference in the underlying authenticate call when you don't know which type of access token you have
    sig { params(token: String).returns(IResult).checked(:always).on_failure(:raise) }
    def authenticate(token)
      ::ProgrammaticAccessToken::Authenticator.perform(token)
    end
  end
end
