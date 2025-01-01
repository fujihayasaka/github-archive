# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Reactor < Platform::Unions::Base
      description "Types that can be assigned to reactions."

      include Platform::Authorization::ReauthorizeScopedObjects

      possible_types(
        Objects::User,
        Objects::Organization,
        Objects::Mannequin,
        Objects::Bot
      )
    end
  end
end
