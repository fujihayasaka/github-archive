# typed: strict
# frozen_string_literal: true

module LoopsHelper
  include GitHub::Memoizer

  # Main token minting method - uses dedicated loops SimpleBox
  sig { params(user_session: UserSession, entry_point: Symbol).returns(Loops::EncryptedToken) }
  def loops_mint_token(user_session, entry_point:)
    user = T.must_because(user_session.user) { "we expect user_session to always have a user" }
    app = T.must_because(loops_app) { "loops_app should always be present" }

    new_access = app.grant(user, { user_session: user_session, entry_point: entry_point })

    # NOTE: despite the name `extended_expiry`, we are actually expiring the tokens much sooner than the default.
    #       the flag is used internally to read from the internal app's `oauth_access_expiry` property.
    token, _ = new_access.redeem(extended_expiry: true)

    encoded = T.must(GitHub.encrypt_and_encode_loops_token(token))

    Loops::EncryptedToken.from(encoded, expiration: new_access.expires_at)
  end

  private

  sig { returns(T.nilable(Integration)) }
  memoize def loops_app
    ::Apps::Privileged.integration(:loops)
  end
end
