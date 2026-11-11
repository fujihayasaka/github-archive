# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class HasStarredCheck < Platform::Loader
      def self.load(viewer_id, entity)
        self.for(viewer_id).load("#{entity.class}:#{entity.id}")
      end

      def initialize(viewer_id)
        @viewer_id = viewer_id
      end

      def fetch(entities)
        HasStarredChecker.new(@viewer_id, entities).run
      end
    end
  end
end
