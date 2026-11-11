# typed: true
# frozen_string_literal: true

module Platform
  module Mutations
    class UpdateSubscription < Platform::Mutations::Base
      docs_category :activity
      description "Updates the state for subscribable subjects."

      minimum_accepted_scopes ["notifications"]

      argument :subscribable_id, ID, "The Node ID of the subscribable object to modify.", required: true, loads: Interfaces::Subscribable
      argument :state, Enums::SubscriptionState, "The new state of the subscription.", required: true
      # This argument is used for custom subscriptions to repo events
      argument :types, [Enums::CustomSubscriptionType], "If the state of the subscription is custom pass in the type to subscribe to.", required: false, required_capabilities: [:mobile_only_schema_mask]
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
        elsif subscribable.is_a?(::Team)
          GitHub.dogstats.increment("graphql.update_subscription.team_subscribable")

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
        process_subscription_update(
          subscribable: subscribable,
          state: inputs[:state],
          user: context[:viewer],
          types: inputs[:types],
          events: inputs[:events]
        )

        { subscribable: subscribable }
      end

      private

      def process_subscription_update(subscribable:, state:, user:, types: [], events: [])
        if subscribable.is_a?(::PullRequest)
          subscribable = subscribable.issue
        end

        case subscribable
        when ::Repository
          case state
          when "custom"
            if types.present?
              user.subscribe_to_thread_types(subscribable, types.map(&:constantize))
            else
              raise Errors::Validation.new("Types input field cannot be empty with custom subscription.")
            end
          when "unsubscribed"
            user.unwatch_repo(subscribable)
          when "subscribed"
            raise Errors::Validation.new("Unable to subscribe") unless user.watch_repo(subscribable)
          when "ignored"
            user.ignore_repo(subscribable)
          when "releases_only"
            user.subscribe_to_thread_types(subscribable, [::Release])
          end
        when ::Commit
          case state
          when "unsubscribed", "ignored"
            Notifications::Subscriptions.unsubscribe_from_thread(user, subscribable)
          when "subscribed"
            Notifications::Subscriptions.subscribe_to_thread(user, subscribable.notifications_list, subscribable, :manual)
          end
        when ::Issue, ::PullRequest, ::Discussion
          case state
          when "unsubscribed", "ignored"
            subscribable.unsubscribe(user) # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          when "subscribed"
            subscribable.subscribe(user, :manual)
          when "custom"
            subscribable.subscribe(user, :manual, events)
          end
        end
      end
    end
  end
end
