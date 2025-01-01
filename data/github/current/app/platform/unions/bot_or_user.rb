# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class BotOrUser < Platform::Unions::Base
      description "Used when either Bot or User are accepted."

      visibility :public, environments: [:dotcom, :enterprise]

      possible_types Objects::Bot, Objects::User
    end
  end
end
