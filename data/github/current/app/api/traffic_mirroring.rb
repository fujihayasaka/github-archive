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
    def self.has_mirrored_request_header?(request)
      request.env[MIRRORED_REQUEST_HEADER_NAME].present?
    end

    def self.is_federated_mirrored_request?(request)
      request.env["HTTP_X_GITHUB_GRAPHQL_FEDERATION_CONTRACT"].present? && request.env[MIRRORED_REQUEST_HEADER_NAME] == "1"
    end

    # Determines the traffic_mirroring value for the GlobalInstrumenter query event
    #
    # @param context [Platform::Context] the GraphQL query context to consult
    # @return [String] the value for the traffic_mirroring field
    def self.query_event_value(context)
      if !context[:is_mirrored_request]
        :not_mirrored
      elsif context[:from_federation] || GitHub.shadow_lab? || GitHub.review_lab?
        :candidate
      else
        :control
      end
    end
  end
end
