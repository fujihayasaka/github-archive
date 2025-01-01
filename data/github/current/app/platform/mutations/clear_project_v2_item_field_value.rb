# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class ClearProjectV2ItemFieldValue < Platform::Mutations::Base
      description "This mutation clears the value of a field for an item in a Project. Currently only text, number, date, assignees, labels, single-select, iteration and milestone fields are supported."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project.", required: true, loads: Objects::ProjectV2
      argument :item_id, ID, "The ID of the item to be cleared.", required: true, loads: Objects::ProjectV2Item
      argument :field_id, ID, "The ID of the field to be cleared.", required: true, loads: Unions::ProjectV2FieldConfiguration

      field :project_v2_item, Objects::ProjectV2Item, "The updated item.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        item = inputs[:item]

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          can_modify = permission.access_allowed?(
            :project_v2_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          ) &&
          item.async_readable_by_viewer?(permission.viewer)

          # If the mutation is clearing the assignees, labels or milestone fields for an Issue or a PR,
          # then we need to additionally check if the viewer can edit the issue/PR also.
          next can_modify if item.draft_issue? || [:assignees, :labels, :milestone].exclude?(inputs[:field].data_type.to_sym)

          can_modify && item.content.async_viewer_can_update?(permission.viewer)
        end
      end

      def resolve(project:, item:, field:)
        item = project.memex_project_items.find_by(id: item.id)
        field = project.memex_project_columns.find_by(id: field.id)
        validate_input(item, field)

        if item.set_column_value(field, extract_clearing_value(field), context[:viewer], false, skip_elasticsearch_updates: true)
          return { project_v2_item: item, errors: [] }
        end

        raise Errors::Unprocessable.new(
          "Cannot clear the field #{field.name}. #{item.errors.full_messages.join(", ")}"
        )
      end

      private

      def validate_input(item, field)
        raise Errors::Validation.new("The item does not exist in the project") if item.nil?
        raise Errors::Validation.new("Cannot clear the field as the item is archived") unless item.archived_at.nil?

        raise Errors::Validation.new("The field does not exist in the project") if field.nil?

        field_type = field.data_type.to_sym
        raise Errors::Validation.new("The title field can not be cleared") if field_type == :title
        raise Errors::Validation.new("Cannot set \"#{field_type}\" type fields on a draft issue.") if item.draft_issue? && [:labels, :milestone].include?(field_type)
      end

      def extract_clearing_value(field)
        field_type = field.data_type.to_sym
        case field_type
        when :assignees, :labels
          []
        when :single_select, :text, :number, :date, :iteration, :milestone
          nil
        else
          raise Errors::Validation.new("Clearing \"#{field_type}\" type fields is not supported.")
        end
      end
    end
  end
end
