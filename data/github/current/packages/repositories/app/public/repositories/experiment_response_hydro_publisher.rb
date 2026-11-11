# typed: strict
# frozen_string_literal: true

module Repositories
  class ExperimentResponseHydroPublisher
    extend GitHub::UTF8

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

    EXCLUDED_MONOLITH_RESPONSE_HEADERS = %w[
      X-RateLimit-Limit
      X-RateLimit-Remaining
      X-RateLimit-Reset
      X-RateLimit-Used
      X-RateLimit-Resource
      Set-Cookie
    ].freeze

    EXCLUDED_REPOSD_RESPONSE_HEADERS = %w[
      connection
      content-length # exclude this because it's added downstream from unicorn
      date
      server
      x-github-backend
      x-github-request-id
      x-github-test-dogstats
      x-github-test-hydroevents
    ].freeze

    AFTER_SINATRA_RESPONSE_HEADERS = %w[
      access-control-allow-origin
      access-control-expose-headers
      content-security-policy
      referrer-policy
      x-content-type-options
      x-frame-options
      x-xss-protection
      x-github-backend
      x-github-request-id
      x-glb-log-append
      server
      x-envoy-upstream-service-time
      transfer-encoding
    ].freeze

    sig { params(topic: String, route: String, request: T.untyped, response: T.untyped, authorized: T.untyped, prettified: T::Boolean, version_metadata: T.nilable(String), event_options: T.untyped).void }
    def self.publish(topic:, route:, request:, response:, authorized:, prettified: false, version_metadata: nil, event_options: {})
      # The api router will rewrite the request path to the repositories/:id form
      # We need to use the original /repos/:owner/:repo/ path if that's what was given.
      request_path = request.path
      if original_nwo = request.env[GitHub::Routers::Api::ThisRepositoryNameWithOwnerKey]
        request_path = request.path.sub(/\/repositories\/\d*\//, "/repos/#{original_nwo}/")
      end

      headers = response.headers.except(*EXCLUDED_MONOLITH_RESPONSE_HEADERS)

      cleaned_response_body = ""
      cleaned_response_body = clean_response_body(response.body.first, headers, prettified)

      message = {
        request_id: GitHub.context[:request_id] || request.env["HTTP_X_GITHUB_REQUEST_ID"],
        method: request.request_method,
        route: route,
        path: request_path,
        query: clean_query_string(request.query_string),
        request_headers: request.env
          .select { |k, _v| ALLOWED_REQUEST_HEADERS.include?(k) }
          .transform_values { |v| utf8(v) }
          .sort_by { |k, _v| k }
          .to_h,
        response_code: response.status,
        response_headers: headers.sort_by { |k, _v| k }.to_h,
        response_body_hash: Digest::SHA256.hexdigest(cleaned_response_body || ""),
        authorized: authorized,
        version_metadata: version_metadata,
        event_options: event_options
      }

      GitHub.hydro_request_analytics_publisher.publish(
        message,
        schema: "github.v1.ExperimentResponse",
        topic: topic
      )
    end

    sig { params(body: T.nilable(String), headers: T::Hash[String, T.untyped], prettified: T::Boolean).returns(T.untyped) }
    def self.clean_response_body(body, headers, prettified)
      return body unless body && headers["Content-Type"].include?("json") && body.include?("?token=")

      parsed_resp = JSON.parse(body, symbolize_names: true)

      parsed_resp = if parsed_resp.is_a?(Array)
        parsed_resp.map { |item| item.except(:_links, :download_url) }
      else
        if parsed_resp.key?(:entries)
          parsed_resp[:entries] = parsed_resp[:entries].map { |entry| entry.except(:_links, :download_url) }
        end
        parsed_resp.except(:_links, :download_url)
      end

      if prettified
        GitHub::JSON.encode(parsed_resp, pretty: true) + "\n"
      else
        GitHub::JSON.encode(parsed_resp)
      end
    rescue # rubocop:disable Lint/RescueException
      # Ignore any errors that occur when trying to parse the response body
      body
    end

    sig { params(query_string: T.nilable(String)).returns(T.nilable(String)) }
    def self.clean_query_string(query_string)
      return query_string unless query_string

      # Remove any token from the query string
      query_string.split("&").reject { |param| param.start_with?("token=") }.join("&")
    end
  end
end
