# typed: strict
# frozen_string_literal: true

module Platform
  module Enums
    class RepositoryCollaboratorAffiliation < Platform::Enums::Base
      docs_category :repos
      description "The affiliation type between collaborator and repository."

      value "ALL", "All collaborators of the repository.", value: "all"
      value "OUTSIDE", "All outside collaborators of an organization-owned repository.", value: "outside"
    end
  end
end
