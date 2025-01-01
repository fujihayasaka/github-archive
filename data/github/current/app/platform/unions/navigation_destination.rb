# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class NavigationDestination < Platform::Unions::Base
      description "Types that can be suggested to a user as navigation destinations"
      visibility :internal

      possible_types(
        Objects::Project,
        Objects::Repository,
        Objects::Team,
      )
    end
  end
end
