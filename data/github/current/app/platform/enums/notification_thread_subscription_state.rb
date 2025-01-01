# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class NotificationThreadSubscriptionState < Platform::Enums::Base
      mobile_only true
      required_capabilities [:access_internal_graphql_notifications]

      description "The possible subscription states of a notification thread."

      value "LIST_IGNORED", "The thread's list is ignored.", value: "list_ignored"
      value "LIST_SUBSCRIBED", "The thread's list is subscribed to.", value: "list_subscribed"
      value "THREAD_SUBSCRIBED", "The thread is subscribed to.", value: "thread_subscribed"
      value "THREAD_TYPE_SUBSCRIBED", "The thread's type is subscribed to.", value: "thread_type_subscribed"
      value "UNSUBSCRIBED", "The thread is not subscribed to.", value: "unsubscribed"
    end
  end
end
