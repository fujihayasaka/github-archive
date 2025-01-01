# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class CheckAnnotationsCount < Platform::Loader

      def self.load(repository, sha, path)
        self.for(repository, sha).load(path)
      end

      def initialize(repository, sha)
        @repository = repository
        @sha = sha
      end

      attr_reader :repository, :sha

      private

      def fetch(paths)
        results = repository.
          annotations_for(sha: sha, filenames: paths, limit: CheckAnnotation::MAX_READ_LIMIT).
          group(:filename).
          count

        Hash.new(0).merge(results)
      end
    end
  end
end
