# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class Followable < Platform::Unions::Base
      description "Entities that can followed by GitHub users"

      possible_types(
        Objects::User,
        Objects::Organization,
      )
    end
  end
end
