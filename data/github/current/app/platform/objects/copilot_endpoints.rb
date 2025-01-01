# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class CopilotEndpoints < Platform::Objects::Base
      description "Copilot endpoint information"

      def self.async_api_can_access?(_permission, _object)
        # This is only invoked from the parent user API, so we don't need to
        # check for viewer permissions.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      def self.async_viewer_can_see?(_permission, _object)
        # Any user can see the endpoints that they should connect to.
        true # rubocop:todo GitHub/GraphqlApiAuthorization
      end

      field :api,
        String,
        "Copilot API endpoint",
        null: false

      def api
        @object.api.endpoint
      end

      field :origin_tracker,
        String,
        "Copilot origin tracker endpoint",
        null: false

      def origin_tracker
        @object.origin_tracker.endpoint
      end

      field :proxy,
        String,
        "Copilot proxy endpoint",
        null: false

      def proxy
        @object.proxy.endpoint
      end

      field :telemetry,
        String,
        "Copilot telemetry endpoint",
        null: false

      def telemetry
        @object.telemetry.endpoint
      end
    end
  end
end
