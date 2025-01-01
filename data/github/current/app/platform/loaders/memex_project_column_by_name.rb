# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MemexProjectColumnByName < Platform::Loader
      def self.load(project, owner, name, viewer)
        self.for.load([project, owner, name, viewer])
      end

      def self.load_all(project, owner, names, viewer)
        Promise.all names.map { |name| self.for.load([project, owner, name, viewer]) }
      end

      def fetch(projects_owners_names)
        projects = []
        owners_by_project = {}
        names = []
        hide_hierarchy_fields_by_owner = {}

        projects_owners_names.each do |project, owner, name, _viewer|
          projects << project
          owners_by_project[project] = owner
          names << name
          hide_hierarchy_fields_by_owner[owner] = !GitHub.flipper[:tasklist_block].enabled?(owner)
        end

        project_columns = ::MemexProjectColumn.where(
          memex_project_id: projects.map(&:id).uniq,
          name: names.uniq
        )
        .map { |c| [[c.memex_project_id, c.name], c] }
        .to_h

        # Filter target sets from fetched data
        results = Hash.new([])

        projects_owners_names.each do |(project, owner, name, viewer)|
          result = project_columns[[project.id, name]]
          next if result.nil?
          next if hide_hierarchy_fields_by_owner[owner] && (result.data_type == "tracks" || result.data_type == "tracked_by")
          next if %w{issue_type}.include?(result.data_type)

          key = [project, owner, name, viewer]
          results.has_key?(key) || results[key] = []
          results[key] << Platform::Helpers::ProjectV2Field.coerce(result)
        end

        results
      end
    end
  end
end
