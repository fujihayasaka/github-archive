# typed: true # rubocop:todo Sorbet/StrictSigil
# frozen_string_literal: true

module Codespaces
  class RepositoryQuery

    # Given a viewer and a list of repository_ids, filters repository_ids and
    # returns ones where the viewer can see the repository (public or they are associated with it).
    def self.visible_repo_ids(viewer, repository_ids)
      visible_repos(viewer, repository_ids).pluck(:id)
    end

    def self.visible_repos(viewer, repository_ids)
      associated_ids = viewer.associated_repository_ids(repository_ids: repository_ids)

      unassociated_ids = repository_ids - associated_ids

      Repository.active.public_scope.where(id: unassociated_ids).or(Repository.active.where(id: associated_ids))
    end
  end
end
