# typed: true
# frozen_string_literal: true

require "securerandom"
require "active_support/notifications"
require "context"

module GitHub
  module Config
    # Provides an interface to instrumenting and subscribing to event
    # notifications using the ActiveSupport::Notifications API.
    #
    #   GitHub.subscribe /*/ do |*args|
    #     event = ActiveSupport::Notifications::Event.new(*args)
    #     # do something with event
    #   end
    #
    #   GitHub.instrument "repo.create", payload
    #
    module Notifications
      def instrumentation_service
        @instrumentation_service ||= ActiveSupport::Notifications
      end

      def instrument(name, payload = {}, &block)
        expanded_payload = ::Context::Expander.expand(payload)
        instrumentation_service.instrument(name, expanded_payload, &block)
      end

      def publish(*args, &block)
        instrumentation_service.publish(*args, &block)
      end

      def subscribe(*args, &block)
        instrumentation_service.subscribe(*args, &block)
      end

      def unsubscribe(subscriber)
        instrumentation_service.unsubscribe(subscriber)
      end
    end
  end

  extend Config::Notifications
end
