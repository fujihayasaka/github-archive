# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ThreadSubscriptionState < Platform::Enums::Base
      description "The possible states of a subscription."

      value "UNAVAILABLE", "The subscription status is currently unavailable.", value: :unavailable
      value "DISABLED", "The subscription status is currently disabled.", value: :disabled
      value "IGNORING_LIST", "The User is never notified because they are ignoring the list", value: :ignoring_list
      value "SUBSCRIBED_TO_THREAD_EVENTS", "The User is notified because they chose custom settings for this thread.", value: :subscribed_to_thread_events
      value "IGNORING_THREAD", "The User is never notified because they are ignoring the thread", value: :ignoring_thread
      value "SUBSCRIBED_TO_LIST", "The User is notified becuase they are watching the list", value: :subscribed_to_list
      value "SUBSCRIBED_TO_THREAD_TYPE", "The User is notified because they chose custom settings for this thread.", value: :subscribed_to_thread_type
      value "SUBSCRIBED_TO_THREAD", "The User is notified because they are subscribed to the thread", value: :subscribed_to_thread
      value "NONE", "The User is not recieving notifications from this thread", value: :none
    end
  end
end
