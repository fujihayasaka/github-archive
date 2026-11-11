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
          hide_hierarchy_fields_by_owner[owner] = !::FeatureFlag.vexi.enabled?(:tasklist_block, owner, default: false)
        end

        project_columns = ::MemexProjectColumn.where(
          memex_project_id: projects.map(&:id).uniq,
          name: names.uniq
        )
        .map { |c| [[c.memex_project_id, c.name], c] }
        .to_h

        # Resolve hidden :org_only issue field ids across all public projects in a single query.
        public_project_ids = projects.select(&:public?).map(&:id).to_set
        org_only_issue_field_ids = if public_project_ids.any?
          candidate_field_ids = project_columns.values
            .select { |c| public_project_ids.include?(c.memex_project_id) && c.issue_field_id? }
            .map(&:issue_field_id)
            .uniq
          # Pass any public project — hidden_issue_field_ids_for only uses it to short-circuit on public?.
          public_project = T.must(projects.find(&:public?))
          ::IssueFieldVisibility.hidden_issue_field_ids_for(public_project, candidate_field_ids)
        else
          Set.new
        end

        # Filter target sets from fetched data
        results = Hash.new([])

        projects_owners_names.each do |(project, owner, name, viewer)|
          result = project_columns[[project.id, name]]
          next if result.nil?
          next if hide_hierarchy_fields_by_owner[owner] && (result.data_type == "tracks" || result.data_type == "tracked_by")
          next if %w{issue_type}.include?(result.data_type)
          next if project.public? && result.issue_field_id? && org_only_issue_field_ids.include?(result.issue_field_id)

          key = [project, owner, name, viewer]
          results.has_key?(key) || results[key] = []
          results[key] << Platform::Helpers::ProjectV2Field.coerce(result)
        end

        results
      end
    end
  end
end
