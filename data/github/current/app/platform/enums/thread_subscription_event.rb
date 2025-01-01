# typed: true
# frozen_string_literal: true

module Platform
  module Enums
    class ThreadSubscriptionEvent < Platform::Enums::Base
      description "The possible custom issues events to subscribe to"
      visibility :internal

      value "CLOSED", "Get notifications when an issue is closed", value: "closed"
      value "REOPENED", "Get notifications when an issue is reopened", value: "reopened"
    end
  end
end
