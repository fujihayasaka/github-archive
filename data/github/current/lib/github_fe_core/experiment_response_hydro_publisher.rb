# typed: strict
# frozen_string_literal: true

module GitHubFeCore
  class ExperimentResponseHydroPublisher
    ALLOWED_REQUEST_HEADERS = T.let(Set.new(%w[
      github.server_id
      HTTP_ACCEPT
      HTTP_REFERER
      HTTP_USER_AGENT
      HTTP_X_FORWARDED_FOR
      HTTP_X_GITHUB_REQUEST_ID
      HTTP_X_ORIGINAL_USER_AGENT
      HTTP_IF_MATCH
      HTTP_IF_NONE_MATCH
      HTTP_IF_MODIFIED_SINCE
      HTTP_IF_UNMODIFIED_SINCE
      REQUEST_METHOD
    ]).freeze, T::Set[String])

    EXCLUDED_RESPONSE_HEADERS = T.let(Set.new(%w[
      X-RateLimit-Limit
      X-RateLimit-Remaining
      X-RateLimit-Reset
      X-RateLimit-Used
      X-RateLimit-Resource
      Set-Cookie
      X-OAuth-Scopes
      X-Accepted-OAuth-Scopes
      X-OAuth-Client-Id
    ]).freeze, T::Set[String])


    # Publish request/response for monolith
    sig { params(route: String, request: T.untyped, response: T.untyped).void }
    def self.publish(route:, request:, response:)
      message = {
        request_id: GitHub.context[:request_id] || request.env["HTTP_X_GITHUB_REQUEST_ID"],
        method: request.request_method,
        route: route,
        path: request.path,
        query: request.query_string,
        request_headers: request.env.select { |k, _v| ALLOWED_REQUEST_HEADERS.include?(k) },
        response_code: response.status,
        response_headers: response.headers.except(*EXCLUDED_RESPONSE_HEADERS),
        response_body_hash: Digest::SHA256.hexdigest(response.body.first || ""),
      }

      GitHub.hydro_request_analytics_publisher.publish(
        message,
        schema: "github.v1.ExperimentResponse",
        topic: "github.experiment.v1.ExperimentResponse"
      )
    end

    # Publish request/response for github-fe-core
    sig { params(route: String, request: T::Hash[Symbol, T.untyped], response: Faraday::Response).void }
    def self.publish_github_fe_core(route:, request:, response:)
      response_headers = (response.env && response.env.response_headers || {}).except(*EXCLUDED_RESPONSE_HEADERS)

      message = {
        method: request[:method],
        path: request[:path],
        query: request[:query],
        request_headers: request[:request_headers],
        request_id: request[:request_id],
        response_body_hash: Digest::SHA256.hexdigest(response.body),
        response_code: response.status,
        response_headers: response_headers,
        route: route,
      }

      GitHub.hydro_request_analytics_publisher.publish(
        message,
        schema: "github.v1.ExperimentResponse",
        topic: "github-fe-core.experiment.v1.ExperimentResponse"
      )
    end
  end
end
