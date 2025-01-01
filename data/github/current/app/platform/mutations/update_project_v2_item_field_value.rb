# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2ItemFieldValue < Platform::Mutations::Base
      description "This mutation updates the value of a field for an item in a Project. Currently only single-select, text, number, date, and iteration fields are supported."
      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project.", required: true, loads: Objects::ProjectV2
      argument :item_id, ID, "The ID of the item to be updated.", required: true, loads: Objects::ProjectV2Item
      argument :field_id, ID, "The ID of the field to be updated.", required: true, loads: Unions::ProjectV2FieldConfiguration
      argument :value, Inputs::ProjectV2FieldValue, "The value which will be set on the field.", required: true

      field :project_v2_item, Objects::ProjectV2Item, "The updated item.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        unless GitHub.projects_new_enabled?
          raise Errors::Unprocessable::ProjectsNewDisabled.new
        end

        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?

          permission.access_allowed?(
            :project_v2_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          ) &&
          inputs[:item].async_readable_by_viewer?(permission.viewer)
        end
      end

      def resolve(project:, item:, field:, value:)
        item = project.memex_project_items.find_by(id: item.id)
        field = project.memex_project_columns.find_by(id: field.id)
        validate_input(item, field)
        value_to_set = extract_value_to_set(field, value)
        if item.set_column_value(field, value_to_set, context[:viewer])
          { project_v2_item: item, errors: [] }
        else
          raise Errors::Unprocessable.new(item.errors.full_messages.join(", "))
        end
      end

      private

      def validate_input(item, field)
        raise Errors::Validation.new("The item does not exist in the project") if item.nil?
        raise Errors::Validation.new("The field does not exist in the project") if field.nil?
        raise Errors::Validation.new("The item is archived and cannot be updated") unless item.archived_at.nil?
        raise Errors::Validation.new("The title field can only be updated on DraftIssues") if field.data_type.to_sym == :title && item["content_type"] != "DraftIssue"
      end

      def extract_value_to_set(field, value)
        case field.data_type.to_sym
        when :title
          raise Errors::Validation.new("Did not receive a text value to update a field of type #{field.data_type.to_sym}") if value.text.nil?
          { title: value.text }
        when :text
          raise Errors::Validation.new("Did not receive a text value to update a field of type #{field.data_type.to_sym}") if !value.arguments.keys.include?(:text)
          value.text
        when :number
          raise Errors::Validation.new("Did not receive a number value to update a field of type #{field.data_type.to_sym}") if !value.arguments.keys.include?(:number)

          number = value.number
          raise Errors::Validation.new(
            "Number values cannot exceed #{MemexProjectColumnValue::NUMBER_VALUE_PRECISION} decimal places"
          ) if !number.nil? && ActiveSupport::NumberHelper.number_to_rounded(
            number,
            precision: MemexProjectColumnValue::NUMBER_VALUE_PRECISION).to_f > number.to_f

          number
        when :date
          raise Errors::Validation.new("Did not receive a date value to update a field of type #{field.data_type.to_sym}") if !value.arguments.keys.include?(:date)
          value.date.nil? ? nil : value.date.iso8601
        when :single_select
          raise Errors::Validation.new("Did not receive a single select option Id to update a field of type #{field.data_type.to_sym}") if !value.arguments.keys.include?(:single_select_option_id)

          is_valid_option_id = value.single_select_option_id.nil? || field.settings["options"].find do |option|
            option["id"] == value.single_select_option_id
          end

          raise Errors::Validation.new("The single select option Id does not belong to the field") unless is_valid_option_id

          value.single_select_option_id
        when :iteration
          raise Errors::Validation.new("Did not receive an iteration Id to update a field of type #{field.data_type.to_sym}") if !value.arguments.keys.include?(:iteration_id)
          is_valid_iteration_id = value.iteration_id.nil? || field.settings_all_iteration(value.iteration_id)
          raise Errors::Validation.new("The iteration Id does not belong to the field") unless is_valid_iteration_id

          value.iteration_id
        else
          raise Errors::Validation.new("The field of type #{field.data_type.to_sym} is currently not supported.")
        end
      end
    end
  end
end
