# typed: true
# frozen_string_literal: true

module GitAuth
  class HydroPublisher
    # Below request headers selected because they are used in lib/github/repo_permissions.rb
    ALLOWED_REQUEST_HEADERS = %w[
      github.server_id
      HTTP_ACCEPT
      HTTP_REFERER
      HTTP_SEC_GITHUB_ALLOWED_ENTERPRISE
      HTTP_X_COUNTRY
      HTTP_X_FORWARDED_FOR
      HTTP_X_GITHUB_MIRRORED_REQUEST
      HTTP_X_GITHUB_MIRRORED_REQUEST_ID
      HTTP_X_GITHUB_REQUEST_ID
      HTTP_X_ORIGINAL_USER_AGENT
      REMOTE_ADDR
      REQUEST_METHOD
    ].freeze

    # Allowable request params to be published
    ALLOWED_REQUEST_PARAMS = %w[
      action
      hostname
      path
      proto
      srcip
      ssh_login
      fingerprint_sha256
    ].freeze

    # Allowed response headers
    ALLOWED_RESPONSE_HEADERS = %w[
      X-GitHub-Enterprise-Redirect
      X-GitHub-Tenant
      X-GitHub-Request-Id
      X-GitHub-GitAuth-Request-Id
      Content-Length
      Content-Type
    ].freeze

    # Publish a gitauth request to the hydro topic
    # @param request [Rack::Request] the request
    # @param request_context [Hash] additional request context
    # @param gitauth_status [Symbol] the gitauth status
    # @param http_status [Integer] the http status
    # @param cap_results [Hash] the cap results (when CAP was evaluated)
    # @param response [String] the response
    # @param response_headers [Hash] the response headers
    # @param duration_ms [Integer] the request duration in ms
    sig { params(request: Rack::Request, request_context: T.nilable(T::Hash[Symbol, T.untyped]), gitauth_status: T.nilable(Symbol), http_status: Integer, cap_results: T.nilable(T::Hash[Symbol, Symbol]), response: String, response_headers: T.nilable(T::Hash[String, T.untyped]), duration_ms: Integer).void }
    def self.publish(request:, request_context:, gitauth_status:, http_status:, cap_results:, response:, response_headers:, duration_ms:)
      request_params = request.POST
      request_headers = request.env.select { |k, _v| ALLOWED_REQUEST_HEADERS.include?(k) }
      request_params = request_params.select { |k, _v| ALLOWED_REQUEST_PARAMS.include?(k) }
      response_headers = response_headers&.select { |k, _v| ALLOWED_RESPONSE_HEADERS.include?(k) }

      GlobalInstrumenter.instrument("gitauth.gitauth_request", {
        mirrored_request_id: request.env["HTTP_X_GITHUB_MIRRORED_REQUEST_ID"] || nil,
        request_headers:,
        request_params:,
        request_context: request_context || {},
        gitauth_status:,
        http_status:,
        cap_results:,
        response: filter_sensitive_response_data(request_params, response),
        response_headers:,
        duration_ms:,
      })
    end

    # Certain response body data is sensitive and should not be published
    sig { params(request_params: T.nilable(T::Hash[String, T.untyped]), response: String).returns(String) }
    def self.filter_sensitive_response_data(request_params, response)
      return response if request_params.nil?
      action = request_params["action"]

      case action
      when "verification-token"
        token = response.strip
        versions = GitHub::Authentication::SignedAuthToken.possible_versions(token).map { |v| v.to_s.split("::").last }
        # If not a possible version, then it's an invalid format and we'll just return the original response
        versions.present? ? versions.to_json : response
      when "git-lfs-authenticate"
        json = JSON.parse(response)
        # Filter the Authorization header if it's in a valid format
        # Otherwise it's an invalid format and we can return the original response
        if json.dig("header", "Authorization").present?
          match = json["header"]["Authorization"].match(/^RemoteAuth (.*)$/)
          if match && GitHub::Authentication::GitAuth::SignedAuthToken.valid_format?(match[1])
            json["header"]["Authorization"] = "RemoteAuth [FILTERED]"
          end
        end
        json.to_json
      else
        response
      end
    end
  end
end
