# typed: true
# frozen_string_literal: true

# Traffic mirroring
module Api
  class TrafficMirroring
    MIRRORED_REQUEST_HEADER_NAME = "HTTP_X_GITHUB_MIRRORED_REQUEST"

    # Determines if a request is mirrored
    #
    # @param request [Request] the request to check
    # @return [Boolean] true if the request is mirrored, false otherwise
    def self.mirrored_request?(request)
      request.env[MIRRORED_REQUEST_HEADER_NAME].present?
    end

    # Determines the traffic_mirroring value for the GlobalInstrumenter query event
    #
    # @param context [Platform::Context] the GraphQL query context to consult
    # @return [String] the value for the traffic_mirroring field
    def self.query_event_value(context)
      if context[:is_mirrored_request]
        (GitHub.shadow_lab? || GitHub.review_lab?) ? :candidate : :control
      else
        :not_mirrored
      end
    end
  end
end
