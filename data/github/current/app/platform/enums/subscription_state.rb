# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class SubscriptionState < Platform::Enums::Base
      description "The possible states of a subscription."

      value "UNSUBSCRIBED", "The User is only notified when participating or @mentioned.", value: "unsubscribed"
      value "RELEASES_ONLY", "The User is notified of new releases, or when participating or @mentioned. Only valid for Repositories.", value: "releases_only", required_capabilities: [:mobile_only_schema_mask]
      value "SUBSCRIBED", "The User is notified of all conversations.", value: "subscribed"
      value "IGNORED", "The User is never notified.", value: "ignored"
      value "CUSTOM", "The User is notified of a custom subset of notifications.", value: "custom", required_capabilities: [:mobile_only_schema_mask]
    end
  end
end
