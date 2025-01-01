# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Subscriptions
    # The checks of a commit updated.
    class CommitChecksUpdated < Platform::Subscriptions::Base

      argument :id, ID, required: true, description: "The global relay id of the commit to subscribe to."

      payload_type ::Platform::Objects::Commit

      attr_reader :commit

      def authorized?(id:)
        super

        # If the viewer can load the underlying root object (the commit),
        # they should be able to receive the subscription because we're
        # relying on the authz checks called as part of the object lookup
        @commit = Helpers::NodeIdentification.typed_object_from_id([Objects::Commit], id, context)
      rescue Platform::Errors::NotFound
        GitHub.dogstats.increment("graphql_subscriptions.unauthorized", tags: ["event:#{stats_event_name}"])
        raise GraphQL::ExecutionError, "Subscription halted"
      end

      def subscribe(id:)
        commit
      end

      def update(id:)
        commit
      end
    end
  end
end
