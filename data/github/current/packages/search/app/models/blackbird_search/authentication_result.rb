# typed: strict
# frozen_string_literal: true

module BlackbirdSearch
  class AuthenticationResult
    sig { returns(T.nilable(BlackbirdActor)) }
    attr_reader :blackbird_actor

    sig { returns(Symbol) }
    attr_reader :auth_type

    sig { returns(T.nilable(Integer)) }
    attr_reader :auth_id

    sig do
      params(
        blackbird_actor: T.nilable(BlackbirdActor),
        auth_type: Symbol,
        auth_id: T.nilable(Integer),
        auth_failed_reason: T.nilable(String)
      ).void
    end
    def initialize(blackbird_actor:, auth_type:, auth_id:, auth_failed_reason:)
      @blackbird_actor = T.let(blackbird_actor, T.nilable(BlackbirdActor))
      @auth_type = auth_type
      @auth_id = T.let(auth_id, T.nilable(Integer))
      @auth_failed_reason = T.let(auth_failed_reason, T.nilable(String))
    end

    sig { returns(T::Boolean) }
    def success?
      !!@blackbird_actor
    end

    sig { returns(T.nilable(String)) }
    def error
      @auth_failed_reason
    end

    sig { returns(T.nilable(T.any(User, Bot))) }
    def actor
      @blackbird_actor&.actor
    end

    sig { returns(T.nilable(ActiveSupport::TimeWithZone)) }
    def expires_at
      actor&.programmatic_access&.expires_at
    end

    # Reconstructs a previously computed AuthenticationResult. Requires an authenticated actor (i.e. User or Bot),
    # and the auth related info retrieved from the previous authentication attempt.
    #
    # Note: This method does not perform authentication. It assumes the caller previously successfully authenticated the actor for the provided
    # auth type and auth id. For initial authentication, callers must use BlackbirdSearch::AuthenticationAttempt.
    #
    # The use case for this behavior is to allow resuming the calculation of an authenticated BlackbirdActor's accessible resources
    # in the context of a background job. Only use this method if you are certain it is the correct behavior to use.
    sig do
      params(
        actor: T.any(User, Bot),
        auth_id: Integer,
        auth_type: Symbol,
        expires_at: T.nilable(ActiveSupport::TimeWithZone),
        request_user_ip: String,
        session_id: String,
        token_kind: String,
      ).returns(AuthenticationResult)
    end
    def self.load_auth_result(actor:, auth_id:, auth_type:, expires_at:, request_user_ip:, session_id:, token_kind:)
      session = nil
      auth_actor = case auth_type
      when :authentication_token
        AuthenticationToken.find_by(id: auth_id)&.authenticatable&.bot
      when :oauth_access
        User.with_oauth_hashed_token(session_id)
      when :user_programmatic_access
        user_programmatic_access = UserProgrammaticAccess.find_by(id: auth_id)
        if user_programmatic_access
          # Required for authorizing accessible organization ids for fine-grained PATs.
          user_programmatic_access.expires_at = expires_at if expires_at
          actor.programmatic_access = user_programmatic_access
          actor
        end
      when :integration
        Integration.find_by(id: auth_id)&.bot
      when :user_session
        session = UserSession.find_by(id: auth_id)
        session&.user
      else
        GitHub.logger.error("unexpected auth type", "gh.auth_type": auth_type, "gh.auth_id": auth_id)
        Failbot.report("unexpected auth type", "gh.auth_type": auth_type, "gh.auth_id": auth_id, catalog_service: "blackbird")
        return AuthenticationResult.new(
          blackbird_actor: nil,
          auth_type: auth_type,
          auth_id: auth_id,
          auth_failed_reason: "unexpected auth type"
        )
      end

      if auth_actor.nil?
        GitHub.logger.error("authenticated actor not found", "gh.auth_type": auth_type, "gh.auth_id": auth_id)
        Failbot.report("authenticated actor not found", "gh.auth_type": auth_type, "gh.auth_id": auth_id, catalog_service: "blackbird")
        return AuthenticationResult.new(
          blackbird_actor: nil,
          auth_type: auth_type,
          auth_id: auth_id,
          auth_failed_reason: "authenticated actor not found"
        )
      end

      AuthenticationResult.new(
        blackbird_actor: BlackbirdActor.new(
          actor: auth_actor,
          session: session,
          request_user_ip: request_user_ip,
          token_kind: token_kind,
        ),
        auth_type: auth_type,
        auth_id: auth_id,
        auth_failed_reason: nil
      )
    end

  end
end
