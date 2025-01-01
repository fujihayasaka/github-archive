# typed: true
# frozen_string_literal: true
module Platform
  module Mutations
    class UnblockUserFromOrganization < Platform::Mutations::Base
      description "Unblock a user from an organization"
      mobile_only true
      minimum_accepted_scopes ["admin:org"]
      extras [:execution_errors]

      argument :organization_id, ID, "The ID of the organization to unblock from", required: true, loads: Objects::Organization
      argument :unblocked_user_id, ID, "The ID of the user to unblock from the organization", required: true, loads: Objects::User

      field :viewer, Objects::User, "The user who is acting for the organization", null: true
      field :unblocked_user, Objects::User, "The user who is being unblocked from the organization", null: true
      error_fields

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :manage_org_blocks_mobile,
          resource: inputs[:organization],
          current_org: inputs[:organization],
          current_repo: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(organization:, unblocked_user:, execution_errors:, **inputs)
        unless organization.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} can't unblock a user without being an admin of " + "#{organization.display_login}.")
        end

        organization.unblock(unblocked_user, actor: context[:viewer])

        {
          viewer: context[:viewer],
          unblocked_user: unblocked_user,
          organization: organization,
          errors: []
        }

      rescue Errors::Forbidden => e
        error_response(e.message, execution_errors, context[:viewer], organization)
      end

      private

      def error_response(message, execution_errors, viewer, organization)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)

        client_error = {
          path: %w(input),
          message: message,
        }

        {
          viewer: viewer,
          unblocked_user: nil,
          errors: [client_error],
        }
      end
    end
  end
end
