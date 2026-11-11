# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIssueType < Platform::Mutations::Base
      description "Creates a new issue type"
      graphql_name "CreateIssueType"
      minimum_accepted_scopes ["admin:org"]

      error_fields

      argument :owner_id, ID, "The ID for the organization on which the issue type is created", required: true, loads: Objects::Organization
      argument :is_enabled, Boolean, "Whether or not the issue type is enabled on the org level", required: true
      argument :name, String, "Name of the new issue type", required: true
      argument :description, String, "Description of the new issue type", required: false
      argument :color, Enums::IssueTypeColor, description: "Color for the issue type", required: false

      field :issue_type, Objects::IssueType, "The newly created issue type", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        permission.access_allowed?(:write_org_issue_types,
          resource: owner,
          current_repo: nil,
          current_org: owner,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      def resolve(execution_errors:, owner:, **inputs)
        issue_type = IssueType.new(
          owner: owner,
          name: inputs[:name],
          description: inputs[:description],
          color: inputs[:color],
          enabled: inputs[:is_enabled]
        )
        return { issue_type: issue_type, errors: [] } if issue_type.save

        Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue_type, execution_errors)
        { issue_type: nil, errors: Platform::UserErrors.mutation_errors_for_model(issue_type) }
      end
    end
  end
end
