# typed: strict
# frozen_string_literal: true

module AppSecurity
  class Domain < GH::Domain::Base
    accessor RepositoryCollaborators
    accessor UserRoles
  end
end
