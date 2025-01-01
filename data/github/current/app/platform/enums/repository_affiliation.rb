# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryAffiliation < Platform::Enums::Base
      description "The affiliation of a user to a repository"

      value "OWNER", "Repositories that are owned by the authenticated user.", value: :owned
      value "COLLABORATOR", "Repositories that the user has been added to as a collaborator.", value: :direct
      value "ORGANIZATION_MEMBER", "Repositories that the user has access to through being a member of an organization. This includes every repository on every team that the user is on.", value: :indirect
    end
  end
end
