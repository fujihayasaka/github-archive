# typed: true
# frozen_string_literal: true

module Platform
  module Loaders
    class MemexProjectColumn < Platform::Loader
      def self.load(project, owner, viewer, id)
        self.for(owner, viewer).load(id)
      end

      def self.load_all(project, owner, viewer, ids: nil)
        loader = self.for(owner, viewer)

        # Once issue_types is GA'd we can remove async_issue_type_column_ids entirely.
        Promise.all([project.async_column_ids, project.async_issue_type_column_ids]).then do |column_ids, issue_type_column_ids|
          filtered_column_ids = column_ids - issue_type_column_ids
          ids = T.let(ids.nil? ? filtered_column_ids : ids & filtered_column_ids, T::Array[String])
          Promise.all(ids.map { |id| loader.load(id) }).then do |columns|
            next columns if IssueFieldsFeature.enabled?(project, actor: viewer)
            columns.reject do |column|
              column.to_field.issue_field_id?
            end
          end
        end
      end

      def initialize(owner, viewer)
        @project_owner = owner
        @viewer = viewer
      end

      def fetch(ids)
        hide_hierarchy_fields = !::FeatureFlag.vexi.enabled?(:tasklist_block, @project_owner, default: false)

        ::MemexProjectColumn.where(id: ids.uniq)
          .sort_by { |c| ids.index(c.id) }
          .reject { |c| hide_hierarchy_fields && (c.data_type == "tracks" || c.data_type == "tracked_by") }
          .reject { |c| %w{issue_type}.include?(c.data_type) }
          .map { |c| [c.id, Platform::Helpers::ProjectV2Field.coerce(c)] }
          .to_h
      end
    end
  end
end
