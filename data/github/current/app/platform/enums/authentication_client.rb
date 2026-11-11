# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AuthenticationClient < Platform::Enums::Base
      docs_category :users
      description "The different kinds of ways to authenticate."
      visibility :internal

      value "WEB", "This authentication record was created from a completed standard web login", value: "web"
      value "USER_SESSION", "This authentication record was created from an existing user session being accessed", value: "user_session"
      value "SIGN_UP", "This authentication record was created when a user registered a new account", value: "sign_up"
      value "PASSWORD_CHANGED", "This authentication record was created when a user was re-authenticated after changing their password", value: "password_changed"
      value "TWO_FACTOR_PARTIAL_SIGN_IN", "This authentication record was created when a user entered a correct password but has not yet completed two-factor authentication", value: "two_factor_partial_sign_in"
    end
  end
end
