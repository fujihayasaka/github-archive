# typed: true
# frozen_string_literal: true

module Platform
  module Interfaces
    module SubscribableThread
      include Platform::Interfaces::Base
      description "Entities that can be subscribed to for web and email notifications."

      field :id, ID, description: "The Node ID of the SubscribableThread object", method: :global_relay_id, null: false

      field :viewer_thread_subscription_status, Enums::ThreadSubscriptionState,
        null: true,
        description: "Identifies the viewer's thread subscription status.",
        extras: [:execution_errors]

      def viewer_thread_subscription_status(execution_errors:)
        return :none if @context[:viewer].nil?

        results do |responses|
          if responses.any?(&:failed?)
            raise Platform::Errors::ServiceUnavailable.new("Subscriptions are currently unavailable. Please try again later.")
          end

          thread_subscription_response = responses.first
          list_subscription_response = responses.second

          ThreadSubscriptionCalculator.new(@object.notifications_list, @object, list_subscription_response, thread_subscription_response).status
        end
      end

      field :viewer_thread_subscription_form_action, Enums::ThreadSubscriptionFormAction,
        null: true,
        description: "Identifies the viewer's thread subscription form action.",
        extras: [:execution_errors]

      def viewer_thread_subscription_form_action(execution_errors:)
        return :none if @context[:viewer].nil?

        results do |responses|
          if responses.any?(&:failed?)
            raise Platform::Errors::ServiceUnavailable.new("Subscriptions are currently unavailable. Please try again later.")
          end

          thread_subscription_response = responses.first
          list_subscription_response = responses.second

          ThreadSubscriptionCalculator.new(@object.notifications_list, @object, list_subscription_response, thread_subscription_response).form_action
        end
      end

      private

      def results(&block)
        async_thread_subscription_status_response = @object
          .async_subscription_status(@context[:viewer])

        async_list_subscription_status_response = @object
          .async_notifications_list
          .then do |notifications_list|
            notifications_list.async_subscription_status(@context[:viewer])
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
