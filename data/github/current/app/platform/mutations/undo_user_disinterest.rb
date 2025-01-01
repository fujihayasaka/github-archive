# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UndoUserDisinterest < Platform::Mutations::Base
      description "Undo a user's disinterest in a feed item"
      minimum_accepted_scopes ["user"]
      required_capabilities [:mobile_only_schema_mask]
      extras [:execution_errors]

      def self.async_api_can_modify?(permission, **inputs)
        true
      end

      argument :identifier, String, "Identifier of the disinterested event", required: true

      error_fields

      def resolve(identifier:, execution_errors:)
        user = context[:viewer]

        GlobalInstrumenter.instrument(
          "feeds.user_disinterest",
          {
            identifier: identifier,
            undo: true,
            actor_id: user.id
          }
        )
        { errors: [] }
      rescue Platform::Errors::Forbidden => e
        error_response(e.message, execution_errors)
      rescue Platform::Errors::NotFound => e
        error_response(e.message, execution_errors)
      end

      private

      def error_response(message, execution_errors)
        Platform::UserErrors.append_legacy_mutation_error_messages_to_context(Array.wrap(message), execution_errors)
        client_error = {
          path: %w(input),
          message: message,
        }
        { errors: [client_error] }
      end
    end
  end
end
