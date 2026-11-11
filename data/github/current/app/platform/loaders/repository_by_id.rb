# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class RepositoryById < Platform::Loader
      def self.load(owner_id, repo_id)
        self.for(owner_id).load(repo_id)
      end

      def self.load_all(owner_id, repo_ids)
        loader = self.for(owner_id)
        Promise.all(repo_ids.map { |id| loader.load(id) })
      end

      def initialize(owner_id)
        @owner_id = owner_id
      end

      def fetch(repo_ids)
        Repository.where(owner_id: @owner_id, id: repo_ids).index_by(&:id)
      end
    end
  end
end
