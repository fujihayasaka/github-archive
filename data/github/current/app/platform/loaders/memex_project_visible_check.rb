# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MemexProjectVisibleCheck < Platform::Loader
      def self.load(viewer, memex_project_id, cap_filter: nil)
        self.for(viewer, cap_filter).load(memex_project_id)
      end

      def initialize(viewer, cap_filter)
        @viewer = viewer
        @cap_filter = cap_filter
      end

      def fetch(memex_project_ids)
        accessible_memex_projects = MemexProject.async_accessible_memexes(
          @viewer,
          memex_project_ids,
          "read"
        ).sync

        accessible_memex_projects = @cap_filter.present? ? @cap_filter.authorized_resources(accessible_memex_projects) : accessible_memex_projects

        accessible_memex_projects.each_with_object(Hash.new(false)) do |memex_project, result|
          result[memex_project.id] = true
        end
      end
    end
  end
end
