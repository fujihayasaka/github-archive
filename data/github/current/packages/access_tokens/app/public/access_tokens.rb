# typed: strict
# frozen_string_literal: true

module AccessTokens
  class << self
    # Checks whether a string looks like an OAuth Access Token.
    #
    # Returns true or false.
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def oauth_access_token?(token)
      OauthAccessTokens::Domain.matches_pattern?(token)
    end

    sig { params(token: T.untyped).returns(T::Boolean) }
    def authnd_token?(token)
      token.is_a?(String) && ::Authnd::Client.authnd_token?(token)
    end

    # Does the given string resemble a valid access token (i.e., either an
    # OAuth access token or an installation access token)?
    #
    # token - A String used as part of an authentication attempt.
    #
    # Returns a Boolean.
    sig { params(token: T.nilable(String)).returns(T::Boolean) }
    def access_token?(token)
      oauth_access_token?(token) || ServerToServerTokens::Domain.matches_pattern?(token) || authnd_token?(token)
    end

    # The token hashed with the default hashing technique for the token
    # type (which is currently Base64-encoded SHA-256 for all types).
    #
    # Returns nil if there was no token and the hashed token otherwise.
    sig { params(token: T.nilable(String)).returns(T.nilable(String)) }
    def hash_token(token)
      return nil unless token
      case token
      when OauthAccessTokens::Domain.token_regex, OauthAccessTokens::Domain::TOKEN_LEGACY_PATTERN
        OauthAccessTokens::Domain.hash_token(token)
      when ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, ServerToServerTokens::Domain::TOKEN_PATTERN_V1
        ServerToServerTokens::Domain.hash_token(token)
      when ProgrammaticAccessTokens::Domain::USER_PATTERN
        ProgrammaticAccessTokens::Domain.hash_token(token)
      else
        Digest::SHA256.base64digest(token)
      end
    end

    sig { params(token: T.nilable(String)).returns(Symbol) }
    def get_token_type(token)
      case token
      when OauthAccessTokens::Domain.token_regex, OauthAccessTokens::Domain::TOKEN_LEGACY_PATTERN
        :oauth_access
      when ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, ServerToServerTokens::Domain::TOKEN_PATTERN_V1
        :authentication_token
      when ProgrammaticAccessTokens::Domain::USER_PATTERN
        :user_programmatic_access
      when RefreshToken::TOKEN_PATTERN_GR1
        :refresh_token
      else
        :unknown
      end
    end

    sig { params(token: T.nilable(String)).returns(String) }
    def token_description(token)
      return "Unknown" unless token
      case
      when token.start_with?("gho_")
        "OAuth access token"
      when token.start_with?("ghp_")
        "Personal access token (classic)"
      when token.start_with?("ghu_")
        "GitHub App user-to-server token"
      when token.start_with?("ghs_", "v1")
        "GitHub App server-to-server token"
      when token.start_with?("ghr_", "r1_")
        "GitHub App refresh token"
      when token.start_with?("github_pat_", "gh1_")
        "Fine-grained personal access token"
      when OauthAccessTokens::Domain::TOKEN_LEGACY_PATTERN.match?(token)
        # Date taken from this blog post: https://github.blog/2021-04-05-behind-githubs-new-authentication-token-formats/
        "OAuth access token created before 2021-04-05"
      else
        "Unknown"
      end
    end

    sig { params(token: T.nilable(String)).returns(Symbol) }
    def valid_checksum_result(token)
      case token
      when OauthAccessTokens::Domain::TOKEN_LEGACY_PATTERN,  ServerToServerTokens::Domain::TOKEN_PATTERN_V1
        :legacy_unsupported
      when OauthAccessTokens::Domain.token_regex
        OauthAccessTokens::Domain.valid_checksum?(token) ? :success : :failure
      when ServerToServerTokens::Domain::TOKEN_PATTERN_GS1, ServerToServerTokens::Domain::TOKEN_PATTERN_V1
        ServerToServerTokens::Domain.valid_checksum?(token) ? :success : :failure
      when ProgrammaticAccessTokens::Domain::USER_PATTERN
        ProgrammaticAccessTokens::Domain.valid_checksum?(token) ? :success : :failure
      when RefreshToken::TOKEN_PATTERN_GR1
        RefreshToken.valid_checksum?(token) ? :success : :failure
      else
        :unknown_failure
      end
    end

    # Attempt to authenticate using token.
    #
    # token - The access token to authenticate with
    # exchange_token - An exchange token that can be used for authentication
    # allow_integrations - Whether the caller supports server to server GitHub App authorization checks
    # allow_user_via_granular_actor - Whether the caller supports user to server GitHub App authorization checks
    # ip - The IP address of the request
    # user_agent - The User-Agent header of the request
    # from - Symbol describing the origin of the attempt
    #
    # Returns a Authentication::Result instance.
    sig do
      params(
        from: T.nilable(Symbol),
        token: T.nilable(String),
        exchange_token: T.nilable(String),
        auth_options: T.untyped,
      ).returns(GitHub::Authentication::Result)
    end
    def try_auth(from: nil, token: nil, exchange_token: nil, auth_options: nil)
      can_use_iet = exchange_token_present_and_supported_as_primary?(exchange_token)
      return GitHub::Authentication::Result.failure(failure_reason: :missing_creds) unless token.present? || can_use_iet

      prefer_iet = GitHub::Authnd::InternalExchangeToken.preferred_as_primary?
      tags = [
        "from:#{from}",
        "can_use_iet:#{can_use_iet}",
        "prefer_iet:#{prefer_iet}",
      ]
      try_auth_timing(tags) do
        if can_use_iet && (!token.present? || prefer_iet)
          exchange_token_authenticate(T.must(exchange_token), **auth_options.merge({ exchange_token_primary: true }))
        elsif can_use_iet
          e = GitHub::Authnd::Experiment::new "authnd.exchange_token_auth"

          e.use do
            access_token_authenticate(token, disable_experiments: true, **auth_options)
          end

          e.try do
            exchange_token_authenticate(T.must(exchange_token), **auth_options)
          end

          e.compare do |control, candidate|
            e.compare_exchange_token_experiment_result(token, control, candidate)
          end

          e.clean do |value|
            e.clean_exchange_token_experiment_result(token, value)
          end

          e.ignore do |control, candidate|
            e.ignore_exchange_token_experiment_result(token, control, candidate)
          end

          e.run
        else
          access_token_authenticate(token, **auth_options)
        end
      end
    end

    sig do
      params(
        tags: T::Array[String],
        block: T.proc.returns(GitHub::Authentication::Result)
      ).returns(GitHub::Authentication::Result)
    end
    private def try_auth_timing(tags, &block)
      if FeatureFlag.vexi.enabled?(:authentication_try_auth_timing, default: false)
        GitHub.dogstats.distribution_time("access_tokens.try_auth.time", tags: tags) do
          block.call
        end
      else
        block.call
      end
    end

    # Authenticate against authnd with an authnd exchange token.
    #
    # Returns a GitHub::Authentication::Result
    sig { params(token: String, auth_options: T.untyped).returns(GitHub::Authentication::Result) }
    def exchange_token_authenticate(token, auth_options)
      primary = auth_options.delete(:exchange_token_primary)
      GitHub.dogstats.increment("authentication.exchange_token", tags: ["primary:#{!!primary}"])

      verifier = GitHub::Authnd.stateless_token_verifier
      begin
        resp = verifier.verify_token(token)
      rescue => e # rubocop:disable Lint/RescueException
        return (result = GitHub::Authentication::Result.token_failure({ authnd_response: resp }))
      end

      GitHub.auth.validate_authnd_access_token_response(token, resp, **auth_options.merge({ via_exchange_token: true }))
    end

    private

    # Is the internal exchange token present and supported for primary auth?
    #
    # exchange_token - The exchange token to check
    #
    # Returns true if the internal exchange token is present and usable for primary authentication.
    sig { params(exchange_token: T.nilable(String)).returns(T::Boolean) }
    def exchange_token_present_and_supported_as_primary?(exchange_token)
      !!(exchange_token.present? && GitHub::Authnd::InternalExchangeToken.attemptable?)
    end

    # Inner method to authenticate with a token
    #
    # token - The token to authenticate with
    # disable_experiments - Whether to disable experiment flags
    # auth_options - Options to pass to the authentication methods
    #
    # Returns a GitHub::Authentication::Result
    sig do
      params(
        token: T.nilable(String),
        auth_options: T.untyped,
      ).returns(GitHub::Authentication::Result)
    end
    def access_token_authenticate(token, auth_options)
      if ProgrammaticAccessTokens::Domain.matches_pattern?(token)
        ProgrammaticAccessTokens.domain.token_authenticate(T.must(token), auth_options)
      elsif ServerToServerTokens::Domain.matches_pattern?(token)
        ServerToServerTokens.domain.token_authenticate(T.must(token), auth_options)
      else
        OauthAccessTokens.domain.token_authenticate(T.must(token), auth_options)
      end
    end
  end
end
