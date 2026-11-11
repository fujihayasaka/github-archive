# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteProjectV2Field < Platform::Mutations::Base
      description "Delete a project field."

      minimum_accepted_scopes ["project"]

      visibility :public, environments: [:dotcom, :enterprise]

      argument :field_id, ID, "The ID of the field to delete.", required: true, loads: Unions::ProjectV2FieldConfiguration

      field :project_v2_field, Unions::ProjectV2FieldConfiguration, "The deleted field.", null: true

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
        viewer = context[:viewer]
        if viewer.user? && viewer.should_verify_email?
          raise Errors::Unprocessable.new("Viewer must have at least one verified email.")
        end

        if field.system_defined?
          raise Errors::Unprocessable.new("Only custom fields can be deleted.")
        end

        # see https://github.com/github/github/pull/250320/files#r1050286954 for context
        if field.respond_to?(:project_field)
          field = field.project_field
        end

        field.async_memex_project.then do |project|
          # this is to memoize the columns as they will be re-ordered after the delete
          # a better solution is to fix the delete_column method so it doesn't assume
          # the columns are already memoized
          project.columns
          success = project.delete_column(field)

          if !success
            raise Errors::Unprocessable.new(field.errors.full_messages.join(", "))
          end

          { project_v2_field: Platform::Helpers::ProjectV2Field.coerce(field) }
        end
      end
    end
  end
end
