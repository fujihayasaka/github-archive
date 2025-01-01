# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ReleaseByTagName < Platform::Loader
      def self.load(repository, slug)
        self.for(repository).load(slug)
      end

      def initialize(repository)
        @repository = repository
      end

      def fetch(tag_names)
        @repository.releases.where(tag_name: tag_names).index_by(&:tag_name)
      end
    end
  end
end
