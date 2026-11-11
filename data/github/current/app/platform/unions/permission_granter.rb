# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PermissionGranter < Platform::Unions::Base
      description "Types that can grant permissions on a repository to a user"
      visibility :public

      possible_types(
        Objects::Organization,
        Objects::Repository,
        Objects::Team,
      )
    end
  end
end
