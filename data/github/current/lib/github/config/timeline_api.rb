# typed: true
# frozen_string_literal: true

require "timeline"

module GitHub
  module Config
    module TimelineApiConfig
      extend self

      # Public: returns a memoized instance of the Timeline::Client
      # configured with various settings for logging, timeouts, etc.
      #
      # Returns an instance of Timeline::Client
      def timeline_api_client(actor = nil)
        TimelineApiClient.factory_client
      end

      def async_timeline_api_client
        TimelineApiClient.async_client
      end

      def timeline_api_is_enabled(actor = nil)
        GitHub.flipper[:timeline_api].enabled?(actor)
      end

      def project_timeline_events_enabled?(actor = nil)
        GitHub.flipper[:project_timeline_events].enabled?(actor)
      end

      alias_method :timeline_api_enabled?, :timeline_api_is_enabled
    end
  end

  extend Config::TimelineApiConfig
end
