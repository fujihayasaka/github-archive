# typed: true
# frozen_string_literal: true

module Platform
  module Unions
    class PermissionGranter < Platform::Unions::Base
      docs_category :orgs
      description "Types that can grant permissions on a repository to a user"
      visibility :public

      possible_types(
        Objects::EnterpriseTeam,
        Objects::Organization,
        Objects::Repository,
        Objects::Team,
      )
    end
  end
end
