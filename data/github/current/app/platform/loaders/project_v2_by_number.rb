# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectV2ByNumber < Platform::Loader
      def self.load(owner_or_source, viewer, number)
        self.for(owner_or_source, viewer).load(number)
      end

      def self.load_all(owner_or_source, viewer, numbers)
        loader = self.for(owner_or_source, viewer)
        Promise.all(numbers.map { |number| loader.load(number) })
      end

      def initialize(owner_or_source, viewer)
        @owner_or_source = owner_or_source
        @viewer = viewer
      end

      def fetch(numbers)
        return @owner_or_source
          .async_memex_projects_scope_for(
            @viewer,
            numbers: numbers,
            filter_ids: @owner_or_source.memex_projects.pluck(:id)
          )
          .then { |memexes| memexes.index_by(&:number) } if @owner_or_source.is_a?(::Repository)

        ::MemexProject.where({
          owner_id: @owner_or_source.id,
          owner_type: @owner_or_source.class.name,
          deleted_at: nil,
          number: numbers,
        }).index_by(&:number)
      end
    end
  end
end
