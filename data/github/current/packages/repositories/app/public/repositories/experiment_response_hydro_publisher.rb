# typed: strict
# frozen_string_literal: true

module Repositories
  class ExperimentResponseHydroPublisher

    ALLOWED_REQUEST_HEADERS = %w[
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
    ].freeze

    EXCLUDED_RESPONSE_HEADERS = %w[
      X-RateLimit-Limit
      X-RateLimit-Remaining
      X-RateLimit-Reset
      X-RateLimit-Used
      X-RateLimit-Resource
      Set-Cookie
      X-OAuth-Scopes
      X-Accepted-OAuth-Scopes
      X-OAuth-Client-Id
    ].freeze


    sig { params(route: String, request: T.untyped, response: T.untyped).void }
    def self.publish(route:, request:, response:)
      # The api router will rewrite the request path to the repositories/:id form
      # We need to use the original /repos/:owner/:repo/ path if that's what was given.
      request_path = request.path
      if original_nwo = request.env[GitHub::Routers::Api::ThisRepositoryNameWithOwnerKey]
        request_path = request.path.sub(/\/repositories\/\d*\//, "/repos/#{original_nwo}/")
      end

      message = {
        request_id: GitHub.context[:request_id] || request.env["HTTP_X_GITHUB_REQUEST_ID"],
        method: request.request_method,
        route: route,
        path: request_path,
        query: request.query_string,
        request_headers: request.env.select { |k, _v| ALLOWED_REQUEST_HEADERS.include?(k) },
        response_code: response.status,
        response_headers: response.headers.except(*EXCLUDED_RESPONSE_HEADERS),
        response_body_hash: Digest::SHA256.base64digest(response.body.first || ""),
      }

      GitHub.hydro_request_analytics_publisher.publish(
        message,
        schema: "github.v1.ExperimentResponse",
        topic: "github.repos.contents.v1.ExperimentResponse"
      )
    end
  end
end
