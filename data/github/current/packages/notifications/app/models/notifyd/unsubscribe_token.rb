# typed: true
# frozen_string_literal: true

module Notifyd
  # An unsubscribe token is token signed with a given user's authorization and
  # includes a payload that, among other things, describes a given scope.
  #
  # Depending on such scope we can decide whether the token is valid to
  # unsubscribe a user, etc.
  class UnsubscribeToken
    EXPIRE_PERIOD = 10.years

    def initialize(action)
      @action = action
    end

    # Returns a token that includes the given payload serialized.
    def sign(user, payload)
      user.signed_auth_token(
        scope: scope,
        data: payload,
        expires: EXPIRE_PERIOD.from_now
      )
    end

    # Returns the user which signed the token and the payload that was included on it.
    def verify(token)
      verification = User.verify_signed_auth_token token: token, scope: scope
      Failbot.push("gh.notifyd.verification_failure_reason": verification.reason) if verification.user.nil?
      [verification.user, verification.data]
    end

    private

    attr_reader :action

    def scope
      "Notifyd:#{action.to_s.camelcase}"
    end
  end
end
