# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteIssueField < Platform::Mutations::Base
      description "Deletes an issue field."
      minimum_accepted_scopes ["admin:org"]
      feature_flag :issue_fields

      error_fields

      argument :field_id, ID, required: true, description: "The ID of the field to delete.", loads: Unions::IssueFields, as: :issue_field
      field :issue_field, Unions::IssueFields, "The deleted issue field.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue_field:, **inputs)
        permission.access_allowed?(:write_org_issue_fields,
          resource: issue_field.owner,
          current_repo: nil,
          current_org: issue_field.owner,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      def resolve(issue_field:, execution_errors:)
        result = Issues.domain.issue_fields.delete_field_by_id(issue_field.id, issue_field.owner)
        case result
        when GH::Result::Ok
          { issue_field: result.value, errors: [] }
        when GH::Result::Error::NotFound
          raise Errors::NotFound.new(result.message)
        when GH::Result::Error::Validation
          Platform::UserErrors.append_legacy_mutation_model_errors_to_context(result.model, execution_errors)
          { issue_field: nil, errors: Platform::UserErrors.mutation_errors_for_model(result.model) }
        when GH::Result::Error
          raise Errors::ServiceUnavailable.new(result.message)
        end
      end
    end
  end
end
