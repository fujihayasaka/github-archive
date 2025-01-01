# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class BlockUser < Platform::Mutations::Base
      description "Block another user"
      required_capabilities [:mobile_only_schema_mask]
      minimum_accepted_scopes ["user"]
      extras [:execution_errors]

      argument :user_id, ID, "Global relay ID of the user to block", required: true

      field :viewer, Objects::User, "The user who is doing the blocking", null: true
      field :blocked_user, Objects::User, "The user who is being blocked", null: true
      error_fields

      def self.async_api_can_modify?(permission, **inputs)
        permission.access_allowed?(
          :update_user,
          resource: permission.viewer,
          current_repo: nil,
          current_org: nil,
          allow_integrations: false,
          allow_user_via_granular_actor: false,
        )
      end

      def resolve(execution_errors:, **inputs)
        viewer = @context[:viewer]
        user_id = inputs[:user_id]

        if user_id.present?
          other_user = Helpers::NodeIdentification.typed_object_from_id([Objects::User], user_id, @context)
        else
          raise Platform::Errors::NotFound.new("user_id not provided")
        end

        can_block_user = viewer.can_block(other_user)

        if can_block_user.blockable?
          result = viewer.block(other_user)
          {
            viewer: viewer,
            blocked_user: other_user,
            errors: [],
          }
        else
          errors = can_block_user.reason
          error_response(errors, execution_errors, viewer)
        end

        rescue Platform::Errors::NotFound
          error_response("User not found", execution_errors, viewer)
      end

      private

      def error_response(message, execution_errors, viewer)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)

        client_error = {
          path: %w(input),
          message: message,
        }

        {
          viewer: viewer,
          blocked_user: nil,
          errors: [client_error],
        }
      end
    end
  end
end
