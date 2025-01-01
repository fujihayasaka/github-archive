# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateProjectV2Field < Platform::Mutations::Base
      description "Update a project field."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]
      feature_flag :memex_project_fields_api

      argument :field_id, ID, "The ID of the field to update.", required: true, loads: Unions::ProjectV2FieldConfiguration
      argument :name, String, "The name to update.", required: false
      argument :single_select_options, [Inputs::ProjectV2SingleSelectFieldOptionInput], "Options for a field of type SINGLE_SELECT. If empty, no changes will be made to the options. If values are present, they will overwrite the existing options for the field.", required: false

      field :project_v2_field, Unions::ProjectV2FieldConfiguration, "The updated field.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, **inputs)
        inputs[:field].async_memex_project.then do |project|
          project.async_owner.then do |owner|
            current_org = owner if owner.organization?

            permission.access_allowed?(
              :project_v2_write,
              current_org: current_org,
              resource: project,
              current_repo: nil,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(field:, **inputs)
        # Reference `MemexProjectColumn`, not the `ProjectV2Field` class
        field = field.project_field if field.is_a?(Platform::Models::SingleSelectField)

        if field.system_defined?
          raise Errors::Unprocessable.new("Only custom fields can be updated.") unless is_status_column?(field)
        end

        field.async_memex_project.then do |project|
          viewer = context[:viewer]
          settings = nil

          if viewer.user? && viewer.should_verify_email?
            raise Errors::Unprocessable.new("Viewer must have at least one verified email.")
          end

          if field.data_type == "single_select" && inputs[:single_select_options].present?
            settings = {}
            options = inputs[:single_select_options].map { |opt| { name: opt.name, color: opt.color, description: opt.description } }
            settings = { options: options }
          end

          success = project.update_column(
            field,
            name: is_status_column?(field) ? nil : inputs[:name], # do not allow changing Status field name
            position: inputs[:position],
            visible: inputs[:visible],
            settings: settings
          )

          if !success
            raise Errors::Unprocessable.new(field.errors.full_messages.join(", "))
          end

          { project_v2_field: Platform::Helpers::ProjectV2Field.coerce(field) }
        end
      end

      def is_status_column?(field)
        field.name == "Status"
      end
    end
  end
end
