# typed: true
# frozen_string_literal: true
# rubocop:disable GitHub/UsePlatformErrors

module Platform
  module Subscriptions
    class PullRequestInfoForListViewUpdated < Platform::Subscriptions::Base
      argument :id, ID, required: true, description: "ID of the pull request to subscribe to."

      field :comments_updated, ::Platform::Objects::PullRequest, null: true, description: "The pull request with the updated state."
      field :commit_checks_updated, ::Platform::Objects::PullRequest, null: true, description: "The pull request with the updated commit checks."
      field :review_decision_updated, ::Platform::Objects::PullRequest, null: true, description: "The pull request with the updated review decision."
      field :status_updated, ::Platform::Objects::PullRequest, null: true, description: "The pull request with the updated state."
      field :title_updated, ::Platform::Objects::PullRequest, null: true, description: "The pull request with the updated title."

      field :pull_request, ::Platform::Objects::PullRequest, null: false, description: "The pull request where the subscription is on."
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

      def get_payload
        {
          pull_request: pull_request,
          comments_updated: nil,
          commit_checks_updated: nil,
          review_decision_updated: nil,
          status_updated: nil,
          title_updated: nil
        }
      end

      def subscribe(**args)
        get_payload
      end

      def update(**args)
        payload = get_payload

        if context[:scope_object]
          payload.each do |key, _value|
            if context[:scope_object][key]
              payload[key] = pull_request
            end
          end
        end

        payload
      end
    end
  end
end
