# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateSubscription < Platform::Mutations::Base
      description "Updates the state for subscribable subjects."

      minimum_accepted_scopes ["notifications"]

      argument :subscribable_id, ID, "The Node ID of the subscribable object to modify.", required: true, loads: Interfaces::Subscribable
      argument :state, Enums::SubscriptionState, "The new state of the subscription.", required: true
      # This argument is used for custom subscriptions to repo events
      argument :types, [Enums::CustomSubscriptionType], "If the state of the subscription is custom pass in the type to subscribe to.", required: false, mobile_only: true
      # This argument is used for custom subscriptions to issue events
      argument :events, [Enums::ThreadSubscriptionEvent], "If the state of the issue subscription is custom pass in the event(s) to subscribe to.", required: false, visibility: :internal

      field :subscribable, Interfaces::Subscribable, "The input subscribable entity.", null: true

      # Determine whether the viewer can access this mutation via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_modify?(permission, subscribable:, **inputs)
        if subscribable.is_a?(::Repository)
          permission.async_owner_if_org(subscribable).then do |org|
            permission.access_allowed?(:v4_update_repo_notifications, current_repo: subscribable, resource: subscribable, current_org: org, allow_integrations: false, allow_user_via_granular_actor: false)
          end
        elsif subscribable.is_a?(::Team) || subscribable.is_a?(::DiscussionPost)
          subscribable.async_organization.then do |org|
            permission.access_allowed?(:v4_update_thread_notifications, current_org: org, resource: org, current_repo: nil, allow_integrations: false, allow_user_via_granular_actor: false)
          end
        else
          current_repo = subscribable.repository
          permission.async_owner_if_org(current_repo).then do |org|
            permission.access_allowed?(:v4_update_thread_notifications, resource: current_repo, current_repo: current_repo, current_org: org, allow_integrations: false, allow_user_via_granular_actor: false)
          end
        end
      end

      def resolve(subscribable:, **inputs)
        begin
          GitHub.newsies.process_subscription_update(
            subscribable: subscribable,
            state: inputs[:state],
            user: context[:viewer],
            types: inputs[:types],
            events: inputs[:events]
          )
        rescue ArgumentError => e
          raise Errors::Validation.new(e.message)
        end

        { subscribable: subscribable }
      end
    end
  end
end
