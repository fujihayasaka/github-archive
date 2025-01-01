# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssueType < Platform::Mutations::Base
      description "Update an issue type"

      graphql_name "UpdateIssueType"

      minimum_accepted_scopes ["admin:org"]
      feature_flag :issue_types

      error_fields

      extras [:execution_errors]

      argument :issue_type_id, ID, "The ID of the issue type to update", loads: Objects::IssueType, required: true
      argument :is_enabled, Boolean, "Whether or not the issue type is enabled for the organization", required: false
      argument :name, String, "The name of the issue type", required: false
      argument :description, String, "The description of the issue type", required: false
      argument :is_private, Boolean, "Whether or not the issue type is applicable to issues in private repositories", required: false
      argument :color, Enums::IssueTypeColor, description: "Color for the issue type", required: false

      field :issue_type, Objects::IssueType, "The updated issue type", null: true

      def self.async_api_can_modify?(permission, issue_type:, **inputs)
        issue_type.async_owner.then do |organization|
          # TODO: Migrate to issue_types write access control: https://github.com/github/issues/issues/8771
          permission.access_allowed?(:update_org,
            resource: organization,
            current_repo: nil,
            current_org: organization,
            allow_integrations: true,
            allow_user_via_granular_actor: true,
            user: permission.viewer
          )
        end
      end

      def resolve(issue_type:, execution_errors:, **inputs)
        issue_type.enabled = inputs[:is_enabled] if inputs.key?(:is_enabled)
        issue_type.name = inputs[:name] if inputs.key?(:name)
        issue_type.description = inputs[:description] if inputs.key?(:description)
        issue_type.color = inputs[:color] if inputs.key?(:color)
        issue_type.private = inputs[:is_private] if inputs.key?(:is_private)

        return { issue_type: issue_type, errors: [] } if issue_type.save

        Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue_type, execution_errors)
        { issue_type: nil, errors: Platform::UserErrors.mutation_errors_for_model(issue_type) }
      end
    end
  end
end
