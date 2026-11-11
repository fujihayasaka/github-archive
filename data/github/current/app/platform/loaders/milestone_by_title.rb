# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MilestoneByTitle < Platform::Loader
      def self.load(repository_id, title)
        self.for(repository_id).load(title)
      end

      def initialize(repository_id)
        @repository_id = repository_id
      end

      def fetch(titles)
        ::Milestone.where(repository_id: @repository_id, title: titles).index_by(&:title)
      end
    end
  end
end
