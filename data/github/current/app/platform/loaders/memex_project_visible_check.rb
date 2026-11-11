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

        available_projects = accessible_memex_projects.reject { |p| p.deleted_at.present? }

        hidden_project_ids = Set.new

        potentially_spammy = available_projects.select(&:user_hidden?)

        # Collect all promises and batch sync with Promise.all to avoid N+1
        hide_promises = potentially_spammy.map { |p| p.async_hide_from_user?(@viewer) }
        hide_results = Promise.all(hide_promises).sync

        potentially_spammy.each_with_index do |project, idx|
          hidden_project_ids.add(project.id) if hide_results[idx]
        end

        available_projects.each_with_object(Hash.new(false)) do |memex_project, result|
          next if hidden_project_ids.include?(memex_project.id)
          result[memex_project.id] = true
        end
      end
    end
  end
end
