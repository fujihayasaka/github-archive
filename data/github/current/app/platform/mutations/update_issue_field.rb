# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateIssueField < Platform::Mutations::Base
      description "Updates an issue field."
      minimum_accepted_scopes ["admin:org"]
      feature_flag :issue_fields

      error_fields

      argument :id, ID, "The ID of the issue field to update.", required: true, loads: Unions::IssueFields, as: :issue_field
      argument :name, String, "The name of the issue field.", required: false
      argument :description, String, "A description of the issue field.", required: false
      argument :options, [Inputs::IssueFieldSingleSelectOptionInput], "The options for the issue field if applicable.", required: false

      field :issue_field, Unions::IssueFields, "The updated issue field.", null: true

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

      def resolve(execution_errors:, issue_field:, name: nil, description: nil, options: nil)
        field_attributes = Issues::IssueFieldUpdateAttributes.new(
          name: name || issue_field.name,
          description: description || issue_field.description
        )

        result = if issue_field.data_type.to_sym == :single_select
          if options&.empty?
            raise Errors::Unprocessable.new("Options are required for single select fields.")
          end
          single_select_options = if options.nil?
            issue_field.options.map do |option|
              Issues::IssueFieldOptionUpdateAttributes.new(
                name: option.name,
                color: option.color,
                description: option.description,
                priority: option.priority,
                option_id: option.id
              )
            end
          else
            options&.map do |option|
              Issues::IssueFieldOptionUpdateAttributes.new(
                name: option.name,
                color: option.color,
                description: option.description,
                priority: option.priority,
                option_id: 0
              )
            end
          end
          Issues.domain.issue_fields.update_single_select_field(
            issue_field: issue_field,
            org: issue_field.owner,
            field_attributes: field_attributes,
            all_options: single_select_options,
          )
        else
          Issues.domain.issue_fields.update_field(
            org: issue_field.owner,
            issue_field: issue_field,
            field_attributes: field_attributes
          )
        end

        case result
        when GH::Result::Ok
          {
            issue_field: result.value,
            errors: []
          }
        when GH::Result::Error::Validation
          message = result.model.errors.full_messages.join(", ")
          Platform::UserErrors.append_legacy_mutation_error_messages_to_context([message], execution_errors)
          { issue_field: nil, errors: Platform::UserErrors.mutation_errors_for_model(result.model, translate: { name_slug: "name" }) }
        when GH::Result::Error
          raise Errors::ServiceUnavailable.new("Encountered an error while updating the issue field: #{result.message}")
        end
      end
    end
  end
end
