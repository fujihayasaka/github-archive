# typed: true
# frozen_string_literal: true

require "graphql/client"
require "graphql/client/http"

# GitHub::Connect is the "low level" interface used by GitHub Connect features
# to establish authenticated communication between GitHub Enterprise and dotcom.
module GitHub
  module Connect
    PER_PAGE = 10
    ALLOWED_DOTCOM_SEARCH_TYPES = %w(code commits issues users topics repositories)

    class ApiError < RuntimeError
      def initialize(message, remote_errors = nil)
        @message       = message
        @remote_errors = remote_errors
      end

      def message
        [@message, @remote_errors].compact.join(": ")
      end
    end

    class TimeoutError < ApiError; end
    class ServiceUnavailableError < ApiError; end
    class InvalidSearchTypeError < ApiError; end
    class ConnectionError < StandardError; end
    class NotInstalled < StandardError; end

    # Public: Token used in the "Authorization" header of GitHub Apps
    #         authenticated calls when a refresh is needed.
    #
    # Returns a String in the "Bearer <JWT>" format, where <JWT> is a
    # JSON Web Token containing the payload verified on dotcom.
    def self.github_app_bearer_token
      key_pem = dotcom_connection.bearer_encoding_key
      iss = dotcom_connection.installation_issuer
      return nil if key_pem.blank? || iss.blank?
      key = OpenSSL::PKey::RSA.new(key_pem)
      now = Time.now.to_i
      payload = {
        iat: now - 60,
        exp: now + (10 * 60),
        iss: iss,
      }
      jwt = JWT.encode(payload, key, "RS256")
      "Bearer #{jwt}"
    end

    def self.auth_headers
      { "Authorization" => "token #{dotcom_connection.uncached_authentication_token}" }
    end

    def self.user_auth_headers(user_token)
      if user_token
        { "Authorization" => "token #{user_token}" }
      else
        {}
      end
    end

    def self.faraday_connection(host = GitHub.dotcom_api_host_name, protocol = GitHub.dotcom_host_protocol)
      options = {
        url: "#{protocol}://#{host}",
      }
      if GitHub.http_proxy_config
        proxy_host = URI.parse(options[:url]).find_proxy("http_proxy" => GitHub.http_proxy_config, "https_proxy" => GitHub.http_proxy_config, "no_proxy" => GitHub.no_proxy_config)
        options[:proxy] = proxy_host.to_s if proxy_host
      end
      Failbot.push github_connect_faraday_url: options[:url]
      Faraday.new(options) do |f|
        f.adapter Faraday.default_adapter
        f.ssl[:verify] = GitHub.dotcom_ssl_verify?
        f.headers["User-Agent"] = "GitHub::Connect/#{GitHub.version_number}"
      end
    end

    def self.github_connect_request(req, path, headers = {}, body = nil, github_connect_accept_type: false, api: true)
      req.url "#{GitHub.dotcom_rest_api_prefix if api}#{path}"
      if body
        req.body = body
        req.headers["Content-Length"] = req.body.size.to_s
        req.headers["Content-Type"] = "application/json"
        req.headers["X-GitHub-Enterprise-Version"] = GitHub.version_number
      end
      req.headers.merge!(github_connect_request_headers)
      req.options.timeout = 15
      req.options.open_timeout = 7
      headers.each { |header, value| req.headers[header] = value }
      if github_connect_accept_type
        req.headers["Accept"] = "application/vnd.github.machine-man-preview+json"
      end
      Failbot.push github_connect_request_method: req.method
    end

    def self.github_app_authenticated(skip_token_refresh = false)
      response = yield
      if !skip_token_refresh && response && response.status == 401
        installation_id = dotcom_connection.installation_id
        conn = self.faraday_connection
        token_response = conn.post do |req|
          headers = {
            "Authorization" => github_app_bearer_token,
          }
          github_connect_request(req, "/app/installations/#{installation_id}/access_tokens", headers, nil, github_connect_accept_type: true)
        end

        return token_response unless token_response.success?

        token = json_parse(token_response.body)["token"]
        ActiveRecord::Base.connected_to(role: :writing) do
          dotcom_connection.authentication_token = token if token
        end
        response = yield
      end
      response
    end

    def self.graphql_client(host = GitHub.dotcom_api_host_name, protocol = GitHub.dotcom_host_protocol)
      @graphql_client ||= begin
        graphql_http_client = GraphQL::Client::HTTP.new("#{protocol}://#{host}#{GitHub.dotcom_graphql_api_prefix}") do
          def headers(context)
            GitHub::Connect.auth_headers.merge({
              "User-Agent" => "GitHub::Connect/#{GitHub.version_number}",
              "GraphQL-Schema" => "public",
            }).merge(GitHub::Connect.github_connect_request_headers)
          end
        end
        graphql_schema = GraphQL::Client.load_schema(graphql_http_client)
        GraphQL::Client.new(schema: graphql_schema, execute: graphql_http_client)
      end
    end

    # Fetches and creates an installation token from GitHub.com with no permissions
    # using GitHub Connect for authentication. Used by Dependabot GHES installs to
    # increase the app rate-limit.
    def self.create_dotcom_permissionless_installation_token(installation_id = dotcom_connection.installation_id)
      raise GitHub::Connect::NotInstalled if installation_id.blank?
      raise report_failure(ServiceUnavailableError.new("API Inaccessible", "breaker open"), "github-connect-permissionless-token") unless circuit_breaker.allow_request?

      begin
        path = "/app/installations/#{installation_id}/access_tokens/permissionless"
        response = self.faraday_connection.post do |request|
          headers = {
            "Authorization" => github_app_bearer_token,
            "User-Agent" => "GitHub::Connect/#{GitHub.version_number}"
          }
          body = GitHub::JSON.dump({ permissions: {}, repository_ids: [] })
          github_connect_request(request, path, headers, body, github_connect_accept_type: true)
        end
        GitHub.logger.info("http.method": "POST", "http.target": path, "http.status": response.status)
        circuit_breaker.success if response.success?

        response
      rescue Faraday::ConnectionFailed => e
        raise report_failure(ServiceUnavailableError.new("API Inaccessible", "connection failed"), "github-connect-permissionless-token")
      rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
        raise report_failure(TimeoutError.new(e.message), "github-connect-permissionless-token", "timeout")
      end
    end

    # Fetches and creates a scoped installation token from GitHub.com using
    # GitHub Connect for authentication.
    def self.create_dotcom_actions_download_token
      raise report_failure(ServiceUnavailableError.new("API Inaccessible", "breaker open"), "github-connect-actions-download-token") unless circuit_breaker.allow_request?

      begin
        installation_id = dotcom_connection.installation_id
        conn = self.faraday_connection
        response = conn.post do |req|
          # Get permissionless token
          github_connect_request(req, "/app/installations/#{installation_id}/access_tokens/permissionless", {
            "Authorization" => github_app_bearer_token,
            "User-Agent" => "GitHub::Connect/#{GitHub.version_number}",
          }, GitHub::JSON.dump({ permissions: {} }), github_connect_accept_type: true)
        end

        if response.success?
          circuit_breaker.success
        end

        response
      rescue Faraday::ConnectionFailed => e
        raise report_failure(ServiceUnavailableError.new("API Inaccessible", "connection failed"), "github-connect-actions-download-token")
      rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
        raise report_failure(TimeoutError.new(e.message), "github-actions-download-token", "timeout")
      end
    end

    # Fetches the verified owners from given owner_logins
    # GitHub Connect for authentication.
    def self.fetch_dotcom_actions_verified_owners(owner_logins)
      raise report_failure(ServiceUnavailableError.new("API Inaccessible", "breaker open"), "github-connect-actions-verified-owners") unless circuit_breaker.allow_request?

      begin
        conn = self.faraday_connection
        request_body = GitHub::JSON.dump({ logins: owner_logins })
        request_headers = auth_headers.merge!({
          "User-Agent" => "GitHub::Connect/#{GitHub.version_number}",
        })
        response = conn.post do |req|
          github_connect_request(req, "/marketplace/actions/verified_owners", request_headers, request_body, github_connect_accept_type: true)
        end

        if response.success?
          circuit_breaker.success
          GitHub::JSON.parse(response.body)
        else
          raise report_failure(ApiError.new("Error: '#{response.status} #{response.body}'"))
        end
      rescue Faraday::ConnectionFailed => e
        raise report_failure(ServiceUnavailableError.new("API Inaccessible", "connection failed"), "github-connect-actions-verified-owners")
      rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
        raise report_failure(TimeoutError.new(e.message), "github-connect-actions-verified-owners", "timeout")
      end
    end

    def self.parse_graphql_query(query)
      graphql_client.parse(query)
    end

    def self.execute_graphql(query, variables: {})
      graphql_client.query(query, variables: variables)
    end

    def self.execute_dotcom_search(type, query, page, headers = {}, user_token = nil)
      raise report_search_failure(ServiceUnavailableError.new("API Inaccessible", "breaker open")) unless circuit_breaker.allow_request?
      raise report_search_failure(InvalidSearchTypeError.new("Invalid Search Type")) unless type.in? ALLOWED_DOTCOM_SEARCH_TYPES

      query = filter_invalid_search_qualifiers(type, query)
      begin
        conn = self.faraday_connection

        response = conn.send(:get) do |req|
          req.url "#{GitHub.dotcom_rest_api_prefix}/search/#{type}", q: query, per_page: PER_PAGE, page: page
          req.headers["Content-Type"] = "application/json"
          req.options.timeout = 5
          req.options.open_timeout = 2

          req.headers.merge!(headers)
          req.headers["Authorization"] = github_app_bearer_token
          req.headers.merge!(user_auth_headers(user_token))
          req.headers.merge!(github_connect_request_headers)
        end
        if response.success?
          circuit_breaker.success
          GitHub::JSON.parse(response.body)
        else
          report_search_failure(ApiError.new("Error: '#{response.status} #{response.body}'"))
        end
      rescue Faraday::ConnectionFailed => e
        report_search_failure(ServiceUnavailableError.new("API Inaccessible", "connection failed"))
      rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
        report_search_failure(TimeoutError.new(e.message), "github_connect_search.timeout")
      end
    end

    # This method is a workaround that can be removed when the API filters
    # invalid search qualifiers (like the UI does), that is, when we close
    # https://github.com/github/github/issues/102659
    def self.filter_invalid_search_qualifiers(type, query)
      # Search already checks this, but due to class manipulation, let's play safe
      raise report_search_failure(InvalidSearchTypeError.new("Invalid Search Type")) unless type.in? ALLOWED_DOTCOM_SEARCH_TYPES

      # Query classes macth type, e.g. "issues" => IssueQuery. Exceptions are
      # "code" (not plural) and "repositories" (=> RepoQuery)
      prefix = type.chomp("itories").singularize.capitalize
      query_class = "Search::Queries::#{prefix}Query".constantize

      # ParsedQuery.parse returns the qualifiers it finds as Arrays,
      # so we'll just strip them out (and keep the String bits)
      all_qualifiers = Search::QueryHelper::field_list
      valid_qualifiers = query_class::field_list
      invalid_qualifiers = all_qualifiers - valid_qualifiers
      parsed_query = Search::ParsedQuery.parse(query, terms: invalid_qualifiers)
      parsed_query.reject { |item| item.is_a? Array }.join(" ")
    end

    def self.report_search_failure(error, metric = "github_connect_search.error")
      circuit_breaker.failure
      Failbot.report(error, { app: "github-connect-search" })
      GitHub.stats.increment(metric) if GitHub.enterprise?
      GitHub.dogstats.increment(metric)
      GitHub::Result.error(error)
      error
    end

    def self.report_failure(error, app = "github-connect-search", metric = "error")
      Failbot.report(error, { app: app })
      GitHub.stats.increment([app.gsub(/-/, "_"), metric].join(".")) if GitHub.enterprise?
      GitHub.dogstats.increment([app.gsub(/-/, "_"), metric].join("."))
      error
    end

    def self.circuit_breaker
      Resilient::CircuitBreaker.get("github-connect-search", {
          instrumenter: GitHub,
          sleep_window_seconds:       5,
          request_volume_threshold:   2,
          error_threshold_percentage: 50,
          window_size_in_seconds:     300,
          bucket_size_in_seconds:     30,
        }
      )
    end

    # Returns true if GHE is linked to dotcom and actions download archive is
    # enabled
    def self.download_dotcom_actions_enabled?
      dotcom_connection.authentication_token? && GitHub.dotcom_download_actions_archive_enabled?
    end

    # Returns true if GHE is linked to dotcom and search is enabled
    def self.unified_search_enabled?
      dotcom_connection.authentication_token? && GitHub.dotcom_search_enabled?
    end

    # Returns true if GHE is linked to dotcom and contribution sync is enabled
    def self.unified_contributions_enabled?
      dotcom_connection.authentication_token? && GitHub.dotcom_contributions_enabled?
    end

    # Returns true if GHE is linked to dotcom and private search is enabled
    def self.unified_private_search_enabled?
      dotcom_connection.authentication_token? && GitHub.dotcom_private_search_enabled?
    end

    # Returns true if GHE is linked to dotcom and Dependabot has been granted access to dotcom
    def self.dependabot_access_to_dotcom_enabled?
      dotcom_connection.authentication_token? && GitHub.ghe_dependabot_access_to_dotcom_enabled?
    end

    def self.post_contribution_data(user_token, user_login, contributions)
      conn = self.faraday_connection
      response = conn.send(:post) do |req|
        self.github_connect_request(req, "/enterprise-installation/contributions", {
          "Authorization" => "token #{user_token}",
        }, {
          login: user_login,
          contributions: contributions,
        }.to_json, github_connect_accept_type: true)
      end

      if response.success?
        true
      else
        raise report_failure(ApiError.new("Error: '#{response.status} #{response.body}'"), "github-connect-contributions") if !response.success?
      end
    rescue Faraday::ConnectionFailed => e
      raise report_failure(ServiceUnavailableError.new("API Inaccessible", "connection failed"), "github-connect-contributions")
    rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
      raise report_failure(TimeoutError.new(e.message), "github-connect-contributions", "timeout")
    end

    def self.remove_user_contributions(user_token)
      conn = self.faraday_connection
      response = conn.send(:delete) do |req|
        self.github_connect_request(req, "/enterprise-installation/user/contributions", {
          "Authorization" => "token #{user_token}",
        }, nil, github_connect_accept_type: true)
      end
      if response.success?
        true
      else
        raise report_failure(ApiError.new("Error: '#{response.status} #{response.body}'"), "github-connect-contributions") if !response.success?
      end
    rescue Faraday::ConnectionFailed => e
      raise report_failure(ServiceUnavailableError.new("API Inaccessible", "connection failed"), "github-connect-contributions")
    rescue Timeout::Error, Faraday::TimeoutError, Net::OpenTimeout => e
      raise report_failure(TimeoutError.new(e.message), "github-connect-contributions", "timeout")
    end

    def self.dotcom_connection
      DotcomConnection.new
    end

    def self.json_parse(json)
      JSON.parse(json)
    rescue Yajl::ParseError
      # An invalid JSON from dotcom shoud be treated as a connection error
      # (it is often a proxy server error message or something to that effect)
      raise ConnectionError
    end

    # Private: Configured headers for dotcom calls (in hash format)
    def self.github_connect_request_headers
      GitHub.dotcom_request_headers.split('\n').map do |line|
        line.chomp.split(": ")
      end.to_h
    end

    # Private: Configure a dev/test environment to use a remote host
    def self.configure_review_lab(lab_name)
      return unless lab_name.present?

      codespace = !!lab_name.ends_with?("githubpreview.dev") || !!lab_name.ends_with?("app.github.dev")
      review_lab = !!lab_name.ends_with?("review-lab.github.com")
      proxima = !!lab_name.ends_with?("ghe.com")
      review_or_codespace = review_lab || codespace
      site_sha = review_lab ? Faraday.send(:get, "https://#{lab_name}/site/sha").body : "GHES"

      GitHub.dotcom_host_name = lab_name
      GitHub.dotcom_api_host_name = review_or_codespace ? lab_name : "api.#{lab_name}"
      GitHub.dotcom_host_protocol = review_or_codespace || proxima ? "https" : "http"
      GitHub.dotcom_rest_api_prefix = review_or_codespace || proxima ? "/api/v3" : ""
      GitHub.dotcom_graphql_api_prefix = review_or_codespace || proxima ? "/api/graphql" : "/graphql"
      GitHub.dotcom_request_headers = "User-Agent: #{site_sha}"
      GitHub.dotcom_upload_host_name = if review_or_codespace
        "#{lab_name}/upload"
      elsif proxima
        "uploads.#{lab_name}"
      else
        "#{lab_name}:3003"
      end
      # Enable license-restricted functionality
      GitHub.dotcom_user_connection_enabled = true
      GitHub.dotcom_contributions_configurable = true
      GitHub.dependency_graph_enabled = true
      GitHub.actions_enabled = true
    end
  end
end
