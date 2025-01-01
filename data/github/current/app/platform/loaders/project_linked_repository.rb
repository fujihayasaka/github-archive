# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectLinkedRepository < Platform::Loader
      def self.load(owner_id, viewer, permission, repo_id)
        self.for(owner_id, viewer, permission).load(repo_id)
      end

      def self.load_all(owner_id, viewer, permission, repo_ids)
        loader = self.for(owner_id, viewer, permission)
        Promise.all(repo_ids.map { |id| loader.load(id) })
      end

      def initialize(owner_id, viewer, permission)
        @owner_id = owner_id
        @viewer = viewer
        @permission = permission
      end

      def fetch(repo_ids)
        repo_ids = ProgrammaticActor::RepositoryFilter.perform(
          actor: @viewer, repository_ids: repo_ids
        ) if ProgrammaticActor::RepositoryFilter.applicable?(@viewer)
        repos = Repository.where(owner_id: @owner_id, id: repo_ids)

        Promise.all(repos.map { |r| @permission.typed_can_see?("Repository", r) }).then do |results|
          repos.zip(results).to_h.filter { |_, result| result }.keys.index_by(&:id)
        end
      end
    end
  end
end
