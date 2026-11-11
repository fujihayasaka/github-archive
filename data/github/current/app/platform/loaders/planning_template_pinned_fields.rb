# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class PlanningTemplatePinnedFields < Platform::Loader
      sig { params(owner: Organization, viewer: T.nilable(User)).returns(Promise[T::Array[Issues::IIssueField]]) }
      def self.load(owner:, viewer: nil)
        self.for(viewer).load(owner)
      end

      sig { params(viewer: T.nilable(User)).void }
      def initialize(viewer = nil)
        @viewer = viewer
      end

      sig { params(inputs: T::Array[Organization]).returns(T::Hash[Organization, T::Array[Issues::IIssueField]]) }
      def fetch(inputs)
        results = {}
        owner_ids = inputs.map(&:id)

        # Batch load all planning templates for all owners in one query
        planning_templates = ::PlanningTemplate
          .where(owner_id: owner_ids, template_type: ::PlanningTemplate::TEMPLATE_TYPES[:default])
          .index_by(&:owner_id)

        # Get all planning template IDs
        planning_template_ids = planning_templates.values.map(&:id)

        # Batch load all pinned fields for all planning templates in one query
        pinned_fields_by_owner = if planning_template_ids.any?
          ::PlanningTemplatesPinnedField
            .where(planning_template_id: planning_template_ids, owner_id: owner_ids)
            .order(:owner_id, :position)
            .group_by(&:owner_id)
        else
          {}
        end

        # Batch load all issue fields in one query
        all_field_ids = pinned_fields_by_owner.values.flatten.map(&:issue_field_id).compact.uniq
        issue_fields = if all_field_ids.any?
          ::IssueField.where(id: all_field_ids).index_by(&:id)
        else
          {}
        end

        # Build results maintaining order for each owner
        inputs.each do |owner|
          pinned_fields = pinned_fields_by_owner[owner.id] || []
          ordered_fields = pinned_fields.filter_map do |pf|
            issue_fields[pf.issue_field_id]
          end

          # Preload owner association and filter by viewer visibility
          if ordered_fields.any?
            ::ActiveRecord::Associations::Preloader.new(records: ordered_fields, associations: :owner).call
            results[owner] = Issues.domain.issue_fields.filter_visible_pinned_fields(ordered_fields, viewer: @viewer)
          else
            results[owner] = []
          end
        end

        results
      end
    end
  end
end
