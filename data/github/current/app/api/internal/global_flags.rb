# typed: true
# frozen_string_literal: true

# Retrieves a list of the globally enabled feature flags
class Api::Internal::GlobalFlags < Api::Internal
  require "feature_management_feature_flags"
  FFMV3 = FeatureManagement::FeatureFlags::Management::V3

  DEFAULT_MANAGEMENT_OPEN_TIMEOUT = 2.0 # seconds
  DEFAULT_MANAGEMENT_TIMEOUT = 5.0 # seconds
  DEFAULT_MAX_RETRIES = 2 # Retry attempts after the initial request
  PAGE_SIZE = 1000
  GLOBAL_FEATURE_FLAGS_CACHE_KEY = "api.internal.global_feature_flags"
  GLOBAL_FEATURE_FLAGS_CACHE_TTL = 5.minutes

  def externally_accessible?
    true
  end

  def require_request_hmac?
    true
  end

  get "/internal/global_flags", operation_id: :internal do
    # Only enable this endpoint for github.com
    deliver_error! 404 unless GitHub.flavor == "GitHub"

    @route_owner = "@github/test-frameworks-reviewers"
    control_access :list_global_flags, resource: current_user, challenge: true, allow_integrations: false, allow_user_via_granular_actor: true

    feature_flags = GitHub.cache.fetch(GLOBAL_FEATURE_FLAGS_CACHE_KEY, ttl: GLOBAL_FEATURE_FLAGS_CACHE_TTL) do
      fetch_feature_flags_from_ffh
    end

    deliver :global_feature_flags_hash, { flag_names: feature_flags }
  end

  private

  def ffh_client
    management_url = GitHub.feature_management_feature_flag_hub_url
    connection = GitHub::FaradayClient::Internal.new(management_url) do |conn|
      conn.options[:open_timeout] = DEFAULT_MANAGEMENT_OPEN_TIMEOUT
      conn.options[:timeout]      = DEFAULT_MANAGEMENT_TIMEOUT

      conn.request :json
      conn.request :retry,
      max: DEFAULT_MAX_RETRIES,
      backoff_factor:      1.2,
      methods:     [:post],
      retry_block: proc { GitHub.dogstats.increment("gh.global_flags.request_retry.count", tags: []) }

      conn.use ::GitHub::FaradayMiddleware::RequestID
      conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.feature_management_feature_flag_hub_mgmt_hmac_key
      conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: "feature_flag_hub", custom_tags: ["service_endpoint:#{management_url}"]
      conn.use CurrentUserMiddleware, current_user.login
      conn.use ::GitHub::FaradayMiddleware::Resilient, name: "feature_flag_hub"
      conn.adapter :typhoeus
    end

    FFMV3::FeatureFlagsClient.new(connection)
  end

  def fetch_feature_flags_from_ffh
    client = ffh_client
    page = 1
    global_flag_names = []
    filter = FFMV3::ListFeatureFlagsFilter.new(
      node_state: FeatureManagement::FeatureFlags::Management::V3::FeatureFlagNodeStateFilter.new(
        name: GitHub::Config::Proxima.current_stamp_or_dotcom,
        state: :SHIPPED
      )
    )

    loop do
      response = client.list_feature_flags(FFMV3::ListFeatureFlagsRequest.new(
        page: page,
        page_size: PAGE_SIZE,
        filter: filter
      ))

      unless response.error.nil?
        error_message = response.error&.meta&.dig(:body)
        raise StandardError,
          "Error listing global feature flags, received status #{response.error&.code}. Error message: '#{error_message}'"
      end

      response.data.features.each do |flag|
        global_flag_names << flag.name
      end

      break if response.data.page >= response.data.total_pages
      page += 1
    end

    global_flag_names
  end

  class CurrentUserMiddleware < ::Faraday::Middleware
    GITHUB_USER_HEADER = "X-GitHub-User".freeze

    def initialize(app, user_login)
      super(app)
      @user_login = user_login
    end

    def call(env)
      env.request_headers[GITHUB_USER_HEADER] = @user_login
      @app.call(env)
    end
  end
end
