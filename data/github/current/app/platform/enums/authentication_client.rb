# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class AuthenticationClient < Platform::Enums::Base
      description "The different kinds of ways to authenticate."
      visibility :internal

      value "WEB", "This authentication attempt came from a web client", value: "web"
    end
  end
end
