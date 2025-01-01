# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class ProjectNextByQuery < Platform::Loader
      def self.load(object, viewer, query)
        self.for(object, viewer).load(query)
      end

      def initialize(object, viewer)
        @object = object
        @viewer = viewer
      end

      def fetch(query)
        filter_ids = []
        query = query.join("")
        parsed_query = Search::Queries::MemexProjectQuery.new(
          query
        ) unless query.blank?

        owner_or_source = case @object
        when ::Issue, ::PullRequest
          T.must(@object.repository).owner
        when ::Repository
          filter_ids = @object.memex_projects.pluck(:id)
          @object
        else
          @object.owner
        end

        return owner_or_source.async_memex_projects_scope_for(
           @viewer,
           filter_ids: filter_ids
         ).then { |memexes| { "" => memexes } } if query.blank?

        {
          "#{query}" => owner_or_source.search_memex_projects(
            query: parsed_query,
            viewer: @viewer,
            limit: nil,
            filter_ids: filter_ids
          ).memex_projects
        }
      end
    end
  end
end
