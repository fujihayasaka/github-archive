# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectNextItemField < Platform::Mutations::Base
      description "Updates a field of an item from a Project."
      minimum_accepted_scopes ["write:org", "repo"]

      required_capabilities [:mobile_only_schema_mask]

      argument :project_id, ID, "The ID of the Project. This field is required.", required: false, loads: Objects::ProjectNext
      argument :item_id, ID, "The id of the item to be updated. This field is required.", required: false, loads: Objects::ProjectNextItem
      argument :field_id, ID, "The id of the field to be updated.", required: false, loads: Objects::ProjectNextField
      argument :field_with_setting_id, ID, "[Deprecated] Use `fieldConstraintId` instead. The id of the field to be updated. Only supports custom fields and status for now.", required: false, loads: Unions::ProjectNextFieldConfiguration

      argument :field_constraint_id, ID, "The id of the field to be updated. Only supports custom fields and status for now.", required: false, loads: Unions::ProjectNextFieldConfiguration
      argument :value, String, "The value which will be set on the field. This field is required.", required: false
      field :project_next_item, Objects::ProjectNextItem, "The updated item.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        Platform::Helpers::ProjectNext.ensure_project_next_api_availability(permission.viewer, permission.oauth_app)

        # Those 3 arguments are in fact _required_ but we need to mark them as _optional_ since we are deprecating this mutation (by annotating all arguments as deprecated).
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:project, self) if inputs[:project].nil?
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:item, self) if inputs[:item].nil?
        Platform::Helpers::ProjectNext.raise_missing_mutation_argument(:value, self) if inputs[:value
        ].nil?

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_next_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          ) &&
          inputs[:item].async_readable_by_viewer?(permission.viewer)
        end
      end

      def resolve(project:, item:, field: nil, field_with_setting: nil, field_constraint: nil, value:)
        item = project.memex_project_items.find_by(id: item.id)
        if item.nil?
          raise Errors::Validation.new("The item does not exist in the project.")
        elsif field.nil? && field_with_setting.nil? && field_constraint.nil?
          raise Errors::Validation.new("You must specify a field, field setting, or field constraint field.")
        elsif item.archived_at != nil
          raise Errors::Validation.new("The item is archived and cannot be updated.")
        else
          update_field = field || field_constraint&.project_field || field_with_setting&.project_field
          updated = case update_field.data_type.to_sym
          when :single_select, :text, :number, :date, :iteration
            item.set_column_value(update_field, value, context[:viewer], false, skip_elasticsearch_updates: true)
          when :title
            if item["content_type"] != "DraftIssue"
              raise Errors::Validation.new("The field of type #{update_field.data_type.to_sym} is currently not supported.")
            end
            item.set_column_value(update_field, { title: value }, context[:viewer], false, skip_elasticsearch_updates: true)
          else
            raise Errors::Validation.new("The field of type #{update_field.data_type.to_sym} is currently not supported.")
          end

          if updated
            { project_next_item: item, errors: [] }
          else
            raise Errors::Unprocessable.new(item.errors.full_messages.join(", "))
          end
        end
      end
    end
  end
end
