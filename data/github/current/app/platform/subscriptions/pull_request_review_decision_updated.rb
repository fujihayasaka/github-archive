# typed: true
# frozen_string_literal: true

# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Subscriptions
    # The review decision of a pull request was changed.
    class PullRequestReviewDecisionUpdated < Platform::Subscriptions::Base

      argument :id, ID, required: true, description: "The pull request to subscribe to."

      payload_type ::Platform::Objects::PullRequest

      attr_reader :pull_request

      def authorized?(id:)
        super

        # If the viewer can load the underlying root object (the pull request),
        # they should be able to receive the subscription because we're
        # relying on the authz checks called as part of the object lookup
        @pull_request = Helpers::NodeIdentification.typed_object_from_id([Objects::PullRequest], id, context)
      rescue Platform::Errors::NotFound
        GitHub.dogstats.increment("graphql_subscriptions.unauthorized", tags: ["event:#{stats_event_name}"])
        raise GraphQL::ExecutionError, "Subscription halted"
      end

      def subscribe(id:)
        pull_request
      end

      def update(id:)
        pull_request
      end
    end
  end
end
