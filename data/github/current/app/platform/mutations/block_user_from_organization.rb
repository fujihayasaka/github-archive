# typed: false
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockUserFromOrganization < Platform::Mutations::Base
      description "Block a user from an organization"
      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["admin:org"]
      extras [:execution_errors]

      argument :organization_id, ID, "The ID of the organization to block from", required: true, loads: Objects::Organization
      argument :blocked_user_id, ID, "The ID of the user to block from the organization", required: true, loads: Objects::User
      argument :duration, Enums::BlockFromOrganizationDuration, "The duration to block the user for", required: true
      argument :notify_blocked_user, Boolean, "Whether or not we send a notification to the blocked user", required: false, default_value: false
      argument :hidden_reason, Enums::ReportedContentClassifiers, "Reason for hiding a user's comments", required: false
      argument :content_id, ID, "The ID of the content that the user was blocked from", required: false

      field :viewer, Objects::User, "The user who is acting for the organization", null: true
      field :blocked_user, Objects::User, "The user who is being blocked from the organization", null: true
      field :blocked_until, Scalars::DateTime, "When the user is blocked until, null if blocked indefinitely", null: true
      field :duration, Enums::BlockFromOrganizationDuration, "The duration the user was blocked for", null: true

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

      def resolve(organization:, blocked_user:, execution_errors:, **inputs)
        unless organization.adminable_by?(context[:viewer])
          raise Errors::Forbidden.new(
            "#{context[:viewer].display_login} can't block a user without being an admin of " + "#{organization.display_login}."
          )
        end

        block = create_block(
          organization: organization,
          blocked_user: blocked_user,
          actor: context[:viewer],
          **inputs,
        )

        if block.valid?
          {
            viewer: context[:viewer],
            blocked_user: blocked_user,
            blocked_until: block.expires_at,
            duration: inputs[:duration],
            errors: []
          }
        else
          raise Platform::Errors::Unprocessable.new("An error occured when blocking user from this organization")
        end

      rescue Platform::Errors::ArgumentError, Platform::Errors::Unprocessable, Errors::Forbidden => e
        error_response(e.message, execution_errors, context[:viewer], organization)
      end

      private

      # Creates and returns an IgnoredUser object with the passed in parameters.
      def create_block(organization:, blocked_user:, **inputs)
        reason = inputs[:hidden_reason].upcase.tr("-", "_") if inputs[:hidden_reason]
        organization.block(blocked_user, actor: context[:viewer],
                                         duration: blocked_duration(inputs[:duration]),
                                         blocked_from_content: blocked_from_content(inputs[:content_id]),
                                         send_notification: inputs[:notify_blocked_user],
                                         minimize_reason: reason)
      end

      # Returns an Integer or nil if the duration is considered to be indefinite.
      def blocked_duration(duration_value)
        duration_value unless duration_value == Enums::BlockFromOrganizationDuration::INDEFINITE_VALUE
      end

      # Finds ands returns a OrgBlockable GraphQL object with the passed in global ID or nil if a nil id is passed in.
      def blocked_from_content(id)
        return nil unless id
        Helpers::NodeIdentification.typed_object_from_id([Platform::Interfaces::OrgBlockable], id, context)
      end

      def error_response(message, execution_errors, viewer, organization)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)
        client_error = {
          path: %w(input),
          message: message,
        }

        {
          viewer: viewer,
          blocked_user: nil,
          blocked_until: nil,
          duration: nil,
          errors: [client_error],
        }
      end
    end
  end
end
