# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class CreateUserDisinterest < Platform::Mutations::Base
      description "Register a user's disinterest in a feed item"
      minimum_accepted_scopes ["user"]
      mobile_only true
      extras [:execution_errors]

      def self.async_api_can_modify?(permission, **inputs)
        true
      end

      argument :identifier, String, "Identifier of the disinterested event", required: true
      argument :reasons, [Enums::FeedDisinterestReason], "Reason why the user is not interested in event", required: true

      error_fields

      def resolve(identifier:, reasons:, execution_errors:)
        user = context[:viewer]

        reasons.each do |reason|
          if ::Conduit::UserDisinterest::REASONS.include?(reason.to_sym)
            GlobalInstrumenter.instrument(
              "feeds.user_disinterest",
              {
              identifier: identifier,
              dismissed_at: Time.now.utc,
              dismissed_reason: reason,
              undo: false,
              actor_id: user.id,
              },
          )
          end
        end

        # cached feed is no longer valid, deleting...
        invalidate_cache(user)

        { errors: [] }
      rescue Platform::Errors::Forbidden => e
        error_response(e.message, execution_errors)
      rescue Platform::Errors::NotFound => e
        error_response(e.message, execution_errors)
      end

      private

      def invalidate_cache(user)
        Conduit::KVBackedCache.invalidate_for(user)
      end

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
