# typed: strict
# frozen_string_literal: true

module Platform
  module Loaders
    class PinnedIssueFields < Platform::Loader
      sig { params(issue_type: IssueType, owner: Organization, viewer: T.nilable(User), repository_id: T.nilable(Integer)).returns(Promise[T::Array[Issues::IIssueField]]) }
      def self.load(issue_type:, owner:, viewer: nil, repository_id: nil)
        self.for(viewer, repository_id).load([issue_type, owner])
      end

      sig { params(viewer: T.nilable(User), repository_id: T.nilable(Integer)).void }
      def initialize(viewer = nil, repository_id = nil)
        @viewer = viewer
        @repository_id = repository_id
      end

      sig { params(inputs: T::Array[[IssueType, Organization]]).returns(T::Hash[[IssueType, Organization], T::Array[Issues::IIssueField]]) }
      def fetch(inputs)
        results = {}
        field_ids_by_key = {}

        # First get all the mappings for all issue types
        inputs.each do |issue_type, owner|
          planning_template = ::PlanningTemplate.where(owner: owner, template_type: ::PlanningTemplate::TEMPLATE_TYPES[:default]).first
          if planning_template
            mappings = ::PlanningTemplatesTypeFieldsMapping.where(
              planning_template: planning_template,
              issue_type: issue_type
            ).order(:position)

            field_ids = mappings.pluck(:issue_field_id).compact
            field_ids_by_key[[issue_type, owner]] = [field_ids, mappings.map(&:position)]
          else
            results[[issue_type, owner]] = []
          end
        end

        # Now batch load all issue fields at once
        if field_ids_by_key.any?
          all_field_ids = field_ids_by_key.values.map(&:first).flatten.uniq
          issue_fields = ::IssueField.where(id: all_field_ids).to_a
          # Preload the owner association to avoid AssociationRefused when viewable_by? accesses it
          ::ActiveRecord::Associations::Preloader.new(records: issue_fields, associations: :owner).call
          fields_by_id = issue_fields.index_by(&:id)

          # Map back to results maintaining order, filtering by viewer visibility using the domain method
          field_ids_by_key.each do |key, (field_ids, positions)|
            ordered_fields = field_ids.zip(positions).map do |id, position|
              [fields_by_id[id], position] if fields_by_id[id]
            end.compact.sort_by { |_, pos| pos }.map(&:first)

            visible_fields = Issues.domain.issue_fields.filter_visible_pinned_fields(ordered_fields, viewer: @viewer, repository_id: @repository_id)
            # Wrap fields with repository context so the GraphQL authorization layer
            # can pass repository_id to viewable_by? during access checks.
            results[key] = if @repository_id
              visible_fields.map { |field| Platform::Models::IssueFieldWithRepoContext.new(field, repository_id: @repository_id) }
            else
              visible_fields
            end
          end
        end

        results
      end
    end
  end
end
