# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module Subscribable
      include Platform::Interfaces::Base
      description "Entities that can be subscribed to for web and email notifications."

      field :id, ID, description: "The Node ID of the Subscribable object", method: :global_relay_id, null: false

      field :viewer_subscription, Enums::SubscriptionState,
        null: true,
        description: "Identifies if the viewer is watching, not watching, or ignoring the subscribable entity.",
        extras: [:execution_errors]

      def viewer_subscription(execution_errors:)
        return "unsubscribed" if @context[:viewer].nil?

        results do |responses|
          if responses.any?(&:failed?)
            raise Platform::Errors::ServiceUnavailable.new("Subscriptions are currently unavailable. Please try again later.")
          end

          thread_subscription = responses.first.value
          list_subscription = responses.second.value

          if thread_subscription.subscribed?
            "subscribed"
          elsif list_subscription.thread_types.any? &&
            (@context[:target] == :internal || Apps::Privileged.capable?(:releases_only_subscription_status, app: @context[:oauth_app]))
            "custom"
          elsif thread_subscription.ignored?
            "ignored"
          elsif list_subscription.thread_types.empty?
            "unsubscribed"
          end
        end
      end

      field :viewer_can_subscribe, Boolean, description: "Check if the viewer is able to change their subscription status for the repository.", null: false

      def viewer_can_subscribe
        return false if @context[:viewer].nil?

        @object.async_subscription_status(@context[:viewer]).then(&:success?)
      end

      field :viewer_can_unsubscribe, Boolean, visibility: :internal, description: "Check if the viewer should be able to unsubscribe from this Subscribable.", null: false

      def viewer_can_unsubscribe
        return false unless @context[:viewer]

        results do |responses|
          next false if responses.any?(&:failed?)

          thread_sub_status = responses.first.value
          list_sub_status = responses.second.value

          (thread_sub_status.subscribed? || list_sub_status.subscribed?) &&
            !thread_sub_status.ignored?
        end
      end

      private

      def results(&block)
        async_thread_subscription_status_response = @object
          .async_subscription_status(@context[:viewer])

        async_list_subscription_status_response = @object
          .async_notifications_list
          .then do |notifications_list|

          if @object == notifications_list
            # Although this is equivalent to the else branch, don't compute it again.
            async_thread_subscription_status_response
          else
            notifications_list.async_subscription_status(@context[:viewer])
          end
        end

        Promise
          .all([
            async_thread_subscription_status_response,
            async_list_subscription_status_response,
          ])
          .then(&block)
      end
    end
  end
end
