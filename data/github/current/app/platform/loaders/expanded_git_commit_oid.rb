# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ExpandedGitCommitOid < Platform::Loader
      def self.load(repository, sha)
        repository.async_network.then do
          self.for(repository).load(sha)
        end
      end

      def self.load_all(repository, shas)
        repository.async_network.then do
          loader = self.for(repository)
          Promise.all(shas.map { |sha| loader.load(sha) })
        end
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(shas)
        @repository.rpc.expand_shas(shas, "commit")
      end
    end
  end
end
