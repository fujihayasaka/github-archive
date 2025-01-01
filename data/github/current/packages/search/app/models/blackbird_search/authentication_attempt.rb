# typed: strict
# frozen_string_literal: true

module BlackbirdSearch
  # Responsible for performing authentication logic for BlackbirdSearch actors. Supports the following forms of authentication:
  # - Signed auth tokens for web-based user sessions.
  # - Authentication tokens for integration installations.
  # - Oauth access for legacy PATs.
  # - User programmatic access for fine-grained PATs.
  # - Integrations for enterprise installations.
  class AuthenticationAttempt

    VALID_AUTH_TYPES = T.let([:authentication_token, :oauth_access, :user_programmatic_access, :integration, :user_session], T::Array[Symbol])

    sig do
      params(
        request_id: String,
        request_user_ip: String,
        token: String,
        token_kind: String,
        user_agent: T.nilable(String)
      ).void
    end
    def initialize(request_id:, request_user_ip:, token:, token_kind:, user_agent:)
      @request_id = request_id
      @request_user_ip = request_user_ip
      @token = token
      @token_kind = token_kind
      @user_agent = user_agent
    end

    # Returns the result of the authentication attempt. If successful, the result will contain a BlackbirdActor instance
    # that can be used to authorize the actor and calculate its accessible resources. If unsuccessful, the result will contain
    # the reason for the failure.
    sig { returns(AuthenticationResult) }
    def result
      @result ||= T.let(AuthenticationResult.new(
        blackbird_actor: blackbird_actor,
        auth_type: auth_type,
        auth_id: auth_id,
        auth_failed_reason: auth_failed_reason,
      ), T.nilable(AuthenticationResult))
    end

    private

    sig { returns(T.nilable(Integer)) }
    attr_reader :auth_id

    sig { returns(T.nilable(String)) }
    attr_reader :auth_failed_reason

    sig { returns(T.nilable(BlackbirdActor)) }
    def api_auth
      if auth_attempt.result.success?
        case auth_type
        when :authentication_token
          @auth_id = ServerToServerTokens.domain.by_hashed_token(ServerToServerTokens::Domain.hash_token(@token))&.id
        when :oauth_access
          @auth_id = auth_attempt.result.user.oauth_access.id
        when :user_programmatic_access
          @auth_id = auth_attempt.result.user.programmatic_access.id
        end

        BlackbirdActor.new(
          actor: auth_attempt.result.user,
          session: nil, # Session is ignored for api actors.
          request_user_ip: @request_user_ip,
          token_kind: @token_kind,
        )
      else
        @auth_failed_reason = T.let(auth_attempt.result.failure_reason.to_s, T.nilable(String))
        # Return `nil` as the blackbird actor value when authentication fails.
        nil
      end
    end

    sig { returns(GitHub::Authentication::Attempt) }
    def auth_attempt
      @auth_attempt ||= T.let(GitHub::Authentication::Attempt.new(
        allow_integrations: true,
        allow_user_via_granular_actor: true,
        from: :blackbird,
        token: @token,
        ip: @request_user_ip,
        user_agent: @user_agent,
        request_id: @request_id,
        password_auth_blocked: true,
      ), T.nilable(GitHub::Authentication::Attempt))
    end

    # Returns the type of authentication used to authenticate the actor.
    # Raises an ArgumentError if the determined token type is not included in the VALID_AUTH_TYPES list.
    sig { returns(Symbol) }
    def auth_type
      @auth_type ||= T.let(begin
        token_type = auth_attempt.token_type
        if token_type == :unknown && @token_kind == Search::Blackbird::Client::ACCESS_TOKEN_KIND_API
          :integration
        elsif token_type == :unknown
          :user_session
        else
          if VALID_AUTH_TYPES.include?(token_type)
            token_type
          else
            raise ArgumentError, "Invalid token type: #{token_type}"
          end
        end
      end, T.nilable(Symbol))
    end

    # Returns a BlackbirdActor instance if the actor was successfully authenticated. Otherwise, returns `nil`.
    # The BlackbirdActor instance allows authorizing the actor and calculate its accessible resources.
    sig { returns(T.nilable(BlackbirdActor)) }
    def blackbird_actor
      return @blackbird_actor if defined?(@blackbird_actor)
      @blackbird_actor = T.let(
        case auth_type
        when :integration
          integration_auth
        when :user_session
          web_auth
        else
          api_auth
        end, T.nilable(BlackbirdActor))
    end

    sig { returns(T.nilable(BlackbirdActor)) }
    def integration_auth
      assertion = Api::IntegrationAssertion.new({ "HTTP_AUTHORIZATION" => "Bearer #{ @token }" })
      if assertion.valid?
        auth_result = GitHub::Authentication::Result.success(assertion.integration.bot)
        @auth_id = assertion.integration.id
        BlackbirdActor.new(
          actor: assertion.integration.bot,
          session: nil, # Session is ignored for integration actors.
          request_user_ip: @request_user_ip,
          token_kind: @token_kind,
        )
      else
        @auth_failed_reason = T.let(assertion.error_message, T.nilable(String))
        # Return `nil` as the blackbird actor value when authentication fails.
        nil
      end
    end

    sig { returns(T.nilable(BlackbirdActor)) }
    def web_auth
      access_token = GitHub::Authentication::SignedAuthToken::Session.verify(
        token: @token,
        scope: Search::Blackbird::TOKEN_SCOPE,
      )


      if access_token.valid?
        @auth_id = T.let(access_token.session.id, T.nilable(Integer))
        BlackbirdActor.new(
          actor: access_token.user,
          session: access_token.session,
          request_user_ip: @request_user_ip,
          token_kind: @token_kind,
        )
      else
        @auth_failed_reason = case
        when access_token.bad_token?       then "token format is invalid"
        when access_token.bad_scope?       then "token is not valid within the scope of this page"
        when access_token.bad_login?       then "token has an invalid user id"
        when access_token.expired?         then "token has expired"
        when access_token.user_suspended?  then "token is for a suspended user"
        when access_token.session_expired? then "token's session has expired"
        when access_token.session_revoked? then "token's session has been revoked"
        else
          "token is malformed or has been tampered with"
        end
        # Return `nil` as the blackbird actor value when authentication fails.
        nil
      end
    end
  end
end
