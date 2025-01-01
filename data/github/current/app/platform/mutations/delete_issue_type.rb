# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteIssueType < Platform::Mutations::Base
      description "Delete an issue type"

      graphql_name "DeleteIssueType"

      minimum_accepted_scopes ["admin:org"]
      feature_flag :issue_types

      error_fields

      extras [:execution_errors]

      argument :issue_type_id, ID, "The ID of the issue type to delete", loads: Objects::IssueType, required: true

      field :deleted_issue_type_id, ID, "The ID of the deleted issue type", null: true

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

      def resolve(issue_type:, execution_errors:)
        id = issue_type.global_relay_id

        issue_type.destroy
        return { deleted_issue_type_id: id, errors: [] } if issue_type.destroyed?

        Platform::UserErrors.append_legacy_mutation_model_errors_to_context(issue_type, execution_errors)
        { deleted_issue_type_id: nil, errors: Platform::UserErrors.mutation_errors_for_model(issue_type) }
      end
    end
  end
end
