# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class DeleteIssueFieldValue < Platform::Mutations::Base
      description "Deletes an issue field value from an issue."
      minimum_accepted_scopes ["public_repo"]
      feature_flag :issue_fields

      argument :issue_id, ID, required: true, loads: Objects::Issue, description: "The ID of the issue."
      argument :field_id, ID, required: true, description: "The ID of the field to delete."

      field :success, Boolean, null: true, description: "Whether the field value was successfully deleted."
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

      def resolve(issue:, field_id:)
        repository = issue.repository
        unless IssueFieldsFeature.enabled?(repository, actor: context[:viewer])
          raise Errors::Forbidden.new("Issue fields feature is not enabled for this repository")
        end

        field_id = Platform::Helpers::NodeIdentification.from_global_id(field_id)[1]
        attr = Issues::IssueFieldDeleteAttributes.new(field_id: field_id.to_i)

        issue_attributes = Issues::UpdateIssueAttributes.new(issue_fields: [attr])
        result = Issues.domain.update(issue, issue_attributes, context[:viewer])

        case result
        when GH::Result::Ok
          { success: true, issue: issue }
        when GH::Result::Error::Validation
          raise Errors::Validation.new(result.message)
        when GH::Result::Error
          raise Errors::Unprocessable.new(result.message)
        end
      end
    end
  end
end
