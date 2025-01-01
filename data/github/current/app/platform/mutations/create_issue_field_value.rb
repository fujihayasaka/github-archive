# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIssueFieldValue < Platform::Mutations::Base
      description "Creates a new issue field value for an issue."
      minimum_accepted_scopes ["public_repo"]
      feature_flag :issue_fields

      argument :issue_id, ID, required: true, loads: Objects::Issue, description: "The ID of the issue."
      argument :issue_field, Inputs::IssueFieldCreateOrUpdateInput, required: true, description: "The field value to create."

      field :issue_field_value, Unions::IssueFieldValue, null: true, description: "The newly created issue field value."
      field :issue, Objects::Issue, null: true, description: "The issue object."

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, issue:, **inputs)
        issue.async_repository.then do |repository|
          permission.async_owner_if_org(repository).then do |org|
            next false unless IssueFieldsFeature.enabled?(repository, actor: permission.viewer)

            permission.access_allowed?(
              :update_issue_field_values,
              resource: issue,
              current_org: org,
              repo: repository,
              allow_integrations: true,
              allow_user_via_granular_actor: true
            )
          end
        end
      end

      def resolve(issue:, issue_field:)
        repository = issue.repository
        unless IssueFieldsFeature.enabled?(repository, actor: context[:viewer])
          raise Errors::Forbidden.new("Issue fields feature is not enabled for this repository")
        end

        Platform::Helpers::IssueFieldValue.create_or_update_field_value(
          issue_field: issue_field,
          issue: issue,
          viewer: context[:viewer],
          action: "create"
        )
      end
    end
  end
end
