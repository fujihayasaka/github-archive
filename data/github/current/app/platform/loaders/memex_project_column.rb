# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MemexProjectColumn < Platform::Loader
      def self.load(project, owner, viewer, id, v2: true)
        self.for(owner, viewer, v2).load(id)
      end

      def self.load_all(project, owner, viewer, v2: true, ids: nil)
        loader = self.for(owner, viewer, v2)

        # Once issue_types is GA'd we can remove async_issue_type_column_ids entirely.
        Promise.all([project.async_issue_type_column_ids, project.async_parent_issue_column_ids, project.async_sub_issues_progress_column_ids])
          .then do |issue_type_column_ids, parent_issue_column_ids, sub_issues_progress_column_ids|
          project.async_column_ids.then do |column_ids|
            column_ids = column_ids - issue_type_column_ids - parent_issue_column_ids - sub_issues_progress_column_ids
            ids = T.let(ids.nil? ? column_ids : ids & column_ids, T::Array[String])
            Promise.all(ids.map { |id| loader.load(id) })
          end
        end
      end

      def initialize(owner, viewer, v2)
        @project_owner = owner
        @viewer = viewer
        @v2 = v2
      end

      def fetch(ids)
        hide_hierarchy_fields = !GitHub.flipper[:tasklist_block].enabled?(@project_owner)

        ::MemexProjectColumn.where(id: ids.uniq)
          .sort_by { |c| ids.index(c.id) }
          .reject { |c| hide_hierarchy_fields && (c.data_type == "tracks" || c.data_type == "tracked_by") }
          .reject { |c| %w{issue_type parent_issue sub_issues_progress}.include?(c.data_type) }
          .map { |c| [c.id, Platform::Helpers::ProjectV2Field.coerce(c, v2: @v2)] }
          .to_h
      end
    end
  end
end
