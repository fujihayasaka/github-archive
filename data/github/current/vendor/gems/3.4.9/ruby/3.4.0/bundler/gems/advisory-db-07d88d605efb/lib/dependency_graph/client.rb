# frozen_string_literal: true

require "faraday"
require "faraday/net_http"

module DependencyGraph
  class Client
    CACHE_KEY_ROOT = "dependency_graph"
    CACHE_TTL = 1.hour

    GET_PACKAGE_REPO_QUERY = <<~GRAPHQL
      query($package_manager: PackageManager!, $package_name: String) {
        packages(packageManager: $package_manager, names: [$package_name]) {
          edges {
            node {
              repositoryNwo
            }
          }
        }
      }
    GRAPHQL

    GET_ESTIMATED_IMPACT_QUERY = <<~GRAPHQL
      query(
        $package_manager: PackageManager!,
        $package_name: String!,
        $version_range: String
      ) {
        allRepositoriesWithVersionRange(
          packageManager: $package_manager,
          packageName: $package_name,
          requirements: $version_range,
          preview: true
        ) {
          estimatedRepositoryCount
        }
      }
    GRAPHQL
    class QueryError < StandardError
      attr_accessor :response

      def initialize(message = nil, response: nil)
        super(message)
        @response = response
      end

      def message
        extract_response_error_message || super
      end

      def status
        response&.status
      end

      def extract_response_error_message
        return unless response&.body

        response.body.dig(:errors, 0, :message)
      end
    end

    attr_accessor :api_url, :last_response, :slow_query_api_url, :hmac_key

    def initialize(**options)
      @api_url = options.fetch(:api_url, ENV.fetch("DEPENDENCY_GRAPH_API_URL", nil))
      @slow_query_api_url = options.fetch(:slow_query_api_url,
        ENV.fetch("DEPENDENCY_GRAPH_API_SLOW_QUERY_URL", nil))
      @hmac_key = options.fetch(:hmac_key, ENV.fetch("DEPENDENCY_GRAPH_API_HMAC_KEY", nil))
    end

    def get_package_repo(package_manager:, package_name:)
      return nil unless enabled?

      cache_key = cache_key("get_package_repo", package_manager, package_name)
      variables = {
        package_manager: package_manager,
        package_name: package_name,
      }
      with_cache(cache_key) do
        data = post(GET_PACKAGE_REPO_QUERY, variables: variables)
        data.dig(:packages, :edges, 0, :node, :repositoryNwo)
      end
    end

    def get_estimated_impact(package_manager:, package_name:, version_range:)
      return nil unless enabled?

      cache_key = cache_key("get_estimated_impact", package_manager, package_name, version_range)
      variables = {
        package_manager: package_manager,
        package_name: package_name,
        version_range: version_range,
      }
      with_cache(cache_key) do
        data = post(GET_ESTIMATED_IMPACT_QUERY,
          variables: variables, options: { slow: true })
        data.dig(:allRepositoriesWithVersionRange, :estimatedRepositoryCount)
      end
    end

    # Since all DG-API functionality is additive, allow us to
    # skip calls to it if it's not fully configured
    def enabled?
      api_url.present? && slow_query_api_url.present? && hmac_key.present?
    end

    private

    def connection
      return @connection if defined?(@connection)

      @connection = Faraday.new do |conn|
        conn.use Faraday::Response::RaiseError
        conn.request :json
        conn.response :json, preserve_raw: true,
          parser_options: { symbolize_names: true }
        conn.adapter Faraday.default_adapter
      end
    end

    def post(query, variables: {}, options: { slow: false })
      open_timeout = options[:slow] ? 10 : 5 # seconds
      timeout = options[:slow] ? 20 : 10 # seconds
      url = query_url(slow: options[:slow])
      params = { query: query, variables: variables }
      @last_response = connection.post(url, params) do |req|
        req.headers["X-Request-Hmac"] = timestamped_hmac
        req.options.open_timeout = open_timeout
        req.options.timeout = timeout
      end
      body = @last_response.body
      if body.key?(:errors)
        raise QueryError.new("Query Error", response: @last_response)
      else
        body[:data]
      end
    end

    def query_url(slow: false)
      base = slow ? slow_query_api_url : api_url
      URI.join(base, "/query")
    end

    def timestamped_hmac
      temp_hmac_token.presence || begin
        key = hmac_key
        timestamp = Time.now.to_i.to_s
        digest = OpenSSL::Digest.new("SHA256")
        hmac = OpenSSL::HMAC.new(key, digest)
        hmac << timestamp
        "#{timestamp}.#{hmac}"
      end
    end

    # Use the `.dg hmac` chatop in #dg-ops to get a temp HMAC token for
    # development, then assign it to DEPENDENCY_GRAPH_API_TEMP_HMAC_TOKEN in
    # .env.local or .env.test. Temp tokens expire after ~10 minutes.
    def temp_hmac_token
      return nil unless Rails.env.local?

      ENV.fetch("DEPENDENCY_GRAPH_API_TEMP_HMAC_TOKEN", nil)
    end

    def cache_key(*parts)
      parts = [CACHE_KEY_ROOT, Rails.env] + parts.map do |part|
        part.to_s.downcase
          # Ensure comparison operators in version ranges are preserved,
          # otherwise both `< x.y.z` and `> x.y.z` would become `_x_y_z`
          # and could result in false positive cache hits.
          .gsub(/[<>=]+/) do |operator|
            case operator
            when "<=" then "_lte_"
            when ">=" then "_gte_"
            when "<" then "_lt_"
            when ">" then "_gt_"
            when "=" then "_eq_"
            else "_"
            end
          end
          .gsub(/\W+/, "_")
      end
      parts.join(":")
    end

    def with_cache(key)
      cached_value = AdvisoryDB.redis.get(key)
      ::GitHub::Telemetry::Logs.logger.debug { "found '#{cached_value}' at #{key}" }
      return JSON.parse(cached_value)["value"] if cached_value.present?

      value = yield
      ::GitHub::Telemetry::Logs.logger.debug { "storing '#{{ value: value }.to_json}' to #{key}" }
      AdvisoryDB.redis.set(key, { value: value }.to_json, ex: CACHE_TTL.to_i)
      value
    end
  end
end
