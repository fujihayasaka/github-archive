# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateProjectV2Field < Platform::Mutations::Base
      description "Create a new project field."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :project_id, ID, "The ID of the Project to create the field in.", required: true, loads: Objects::ProjectV2
      argument :data_type, Enums::ProjectV2CustomFieldType, "The data type of the field.", required: true
      argument :name, String, "The name of the field.", required: true
      argument :single_select_options, [Inputs::ProjectV2SingleSelectFieldOptionInput], "Options for a single select field. At least one value is required if data_type is SINGLE_SELECT", required: false

      field :project_v2_field, Unions::ProjectV2FieldConfiguration, "The new field.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        inputs[:project].async_owner.then do |owner|
          current_org = owner if owner.organization?
          permission.access_allowed?(
            :project_v2_write,
            current_org: current_org,
            resource: inputs[:project],
            current_repo: nil,
            allow_integrations: true,
            allow_user_via_granular_actor: true
          )
        end
      end

      def resolve(project:, data_type:, **inputs)
        viewer = context[:viewer]
        settings = nil
        name = inputs[:name]

        if viewer.user? && viewer.should_verify_email?
          raise Errors::Unprocessable.new("Viewer must have at least one verified email.")
        end

        data_type = data_type.underscore
        if data_type == "single_select"
          if inputs[:single_select_options].blank?
            raise Errors::Unprocessable.new("At least one singleSelectOption is required for data_type SINGLE_SELECT.")
          end
          settings = {}
          options = inputs[:single_select_options].map { |opt| { name: opt.name, color: opt.color, description: opt.description } }
          settings = { options: options }
        end

        field = project.add_user_defined_column(
          name: name,
          data_type: ,
          position: inputs[:position],
          creator: viewer,
          settings: settings
        )

        if !field.persisted?
          raise Errors::Unprocessable.new(field.errors.full_messages.join(", "))
        end

        { project_v2_field: Platform::Helpers::ProjectV2Field.coerce(field) }
      end
    end
  end
end
