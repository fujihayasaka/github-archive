# typed: strict
# frozen_string_literal: true

module Notifyd
  # A tracking token is token signed with a given user's authorization and
  # includes a payload that, among other things, describes a given scope.
  class Authentication
    EXPIRE_PERIOD = T.let(10.years, ActiveSupport::Duration)

    sig { params(action: T.any(String, Symbol)).void }
    def initialize(action)
      @action = action
    end

    # Returns a token that includes the given payload serialized.
    sig { params(user: User, payload: T.untyped).returns(String) }
    def sign(user, payload)
      user.signed_auth_token(
        scope: scope,
        data: payload,
        expires: EXPIRE_PERIOD.from_now
      )
    end

    # Returns the user which signed the token and the payload that was included on it.
    sig { params(token: String).returns(T::Array[T.untyped]) }
    def verify(token)
      verification = User.verify_signed_auth_token token: token, scope: scope
      Failbot.push("gh.notifyd.verification_failure_reason": verification.reason) if verification.user.nil?
      [verification.user, verification.data]
    end

    private

    sig { returns(T.any(String, Symbol)) }
    attr_reader :action

    sig { returns(String) }
    def scope
      "Notifyd:#{action.to_s.camelcase}"
    end
  end
end
