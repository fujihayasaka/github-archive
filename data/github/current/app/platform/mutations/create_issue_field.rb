# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateIssueField < Platform::Mutations::Base
      description "Creates a new issue field."
      minimum_accepted_scopes ["admin:org"]
      feature_flag :issue_fields

      error_fields

      argument :owner_id, ID, "The ID of the organization where the issue field will be created.", required: true, loads: Objects::Organization
      argument :name, String, "The name of the issue field.", required: true
      argument :description, String, "A description of the issue field.", required: false
      argument :data_type, Enums::IssueFieldDataType, "The data type of the issue field.", required: true
      argument :options, [Inputs::IssueFieldSingleSelectOptionInput], "The options for the issue field if applicable.", required: false

      field :issue_field, Unions::IssueFields, "The newly created issue field.", null: true

      extras [:execution_errors]

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, owner:, **inputs)
        permission.access_allowed?(:write_org_issue_fields,
          resource: owner,
          current_repo: nil,
          current_org: owner,
          allow_integrations: true,
          allow_user_via_granular_actor: true
        )
      end

      def resolve(execution_errors:, owner:, name:, description: nil, data_type:, options: nil)
        field_attributes = Issues::IssueFieldNewAttributes.new(
          name: name,
          data_type: data_type.to_s,
          description: description
        )

        result = if data_type.to_sym == :single_select
          if options.nil? || options.empty?
            raise Errors::Unprocessable.new("Options are required for single select fields.")
          end
          single_select_options = options&.map do |option|
            Issues::IssueFieldOptionNewAttributes.new(
              name: option.name,
              color: option.color,
              description: option.description,
              priority: option.priority
            )
          end
          Issues.domain.issue_fields.create_single_select_field(
            org: owner,
            name: field_attributes.name,
            description: field_attributes.description,
            options: single_select_options,
            actor: context[:viewer]
          )
        else
          Issues.domain.issue_fields.create_field(
            org: owner,
            name: field_attributes.name,
            data_type: field_attributes.data_type,
            actor: context[:viewer],
            description: field_attributes.description
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
          raise Errors::ServiceUnavailable.new("Encountered an error while creating the issue field: #{result.message}")
        end
      end
    end
  end
end
