# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class SetIssueFieldValue < Platform::Mutations::Base
      description "Sets the value of an IssueFieldValue."
      minimum_accepted_scopes ["public_repo"]
      feature_flag :issue_fields

      argument :issue_id, ID, "The ID of the Issue to set the field value on.", required: true, loads: Objects::Issue
      argument :issue_fields, [Inputs::IssueFieldCreateOrUpdateInput], "The issue fields to set on the issue", required: true
      field :issue_field_values, [Unions::IssueFieldValue], "The issue field values that were created or updated.", null: true
      field :issue, Objects::Issue, "The issue where the field values were set.", null: true

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

      def resolve(issue:, issue_fields:)
        repository = issue.repository
        unless IssueFieldsFeature.enabled?(repository, actor: context[:viewer])
          raise Errors::Forbidden.new("Issue fields feature is not enabled for this repository")
        end

        field_value_attributes = issue_fields.map do |issue_field|
          field_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field.field_id)[1]
          if issue_field.delete
            Issues::IssueFieldDeleteAttributes.new(field_id: field_id.to_i)
          elsif issue_field.text_value
            Issues::IssueFieldTextValueAttributes.new(field_id: field_id.to_i, text_value: issue_field.text_value)
          elsif issue_field.date_value
            Issues::IssueFieldDateValueAttributes.new(field_id: field_id.to_i, date_value: issue_field.date_value)
          elsif issue_field.single_select_option_id
            option_id = Platform::Helpers::NodeIdentification.from_global_id(issue_field.single_select_option_id)[1]
            Issues::IssueFieldSingleSelectValueAttributes.new(field_id: field_id.to_i, option_id: option_id.to_i)
          elsif issue_field.number_value
            Issues::IssueFieldNumberValueAttributes.new(
              field_id: field_id.to_i,
              number_value: issue_field.number_value
            )
          else
            raise Errors::Validation.new("You must provide a valid value to match the selected type.")
          end
        end

        issue_attributes = Issues::UpdateIssueAttributes.new(
          issue_fields: field_value_attributes
        )
        result = Issues.domain.update(issue, issue_attributes, context[:viewer])

        case result
        when GH::Result::Ok
          values = field_value_attributes.map do |attr|
            Issues.domain.issue_fields.get_issue_field_value(issue.repository_id, issue.id, attr.field_id)
          end.compact
          { issue_field_values: values, issue: issue }
        when GH::Result::Error::Validation
          raise Errors::Validation.new(result.message)
        when GH::Result::Error
          raise Errors::Unprocessable.new(result.message)
        end
      end
    end
  end
end
