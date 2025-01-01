# typed: true
# frozen_string_literal: true

require "turboghas"
require "github/faraday_adapter/persistent_excon"

class ::Turboghas::Proto::GetCommittersResponse::Committer
  def display_login
    User.to_display_login(login) # rubocop:disable GitHub/DoNotAllowLogin
  end

  def name_with_display_owner
    owner, _, name = repository_nwo.partition("/")
    "#{ User.to_display_login(owner) }/#{ name }"
  end
end

class ::Turboghas::Proto::GetEnterpriseUsersResponse::User
  def display_login
    User.to_display_login(login) # rubocop:disable GitHub/DoNotAllowLogin
  end
end

class ::Turboghas::Proto::GetOrganizationsResponse::Organization
  def display_login
    User.to_display_login(login) # rubocop:disable GitHub/DoNotAllowLogin
  end
end

module GitHub
  class Turboghas

    SERVICE_NAME = "turboghas"
    FAILBOT_APP_NAME = "github-turboghas-client"

    class ResponseError < StandardError
      attr_reader :error
      def initialize(error)
        @error = error
        super(error)
      end
    end

    def self.content_type
      return "application/json" if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      "application/protobuf"
    end

    def self.new_client(connection:)
      ::Turboghas::Proto::AdvancedSecurityAPIClient.new(connection, { content_type: content_type })
    end

    def self.client
      @client ||= new_client(connection: connection)
    end

    def self.connection(timeout: 5, open_timeout: 1)
      GitHub::FaradayClient::Internal.new(url: GitHub.turboghas_url) do |conn|
        conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.turboghas_url
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.turboghas_hmac_key
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::TenantContext
        conn.use GitHub::FaradayMiddleware::Datadog,
          stats: GitHub.dogstats,
          service_name: "turboghas",
          catalog_service: "github/code_scanning",
          tracked_availability_slos: ["turboghas"],
          enable_path_tag: true

        conn.request :retry,
          max:                 3,
          interval:            0.050,
          interval_randomness: 0.5,
          backoff_factor:      1.2,
          retry_statuses: [429, 502, 503, 504],
          # In Twirp, everything is a POST
          methods:     [:post],
          exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError, Faraday::ServerError],
          retry_block: retry_block(timeout: timeout)

        conn.use GitHub::FaradayMiddleware::Resilient, name: "turboghas:AdvancedSecurityAPI", options: {
          instrumenter: GitHub,
          sleep_window_seconds: 5,
          error_threshold_percentage: 50,
          window_size_in_seconds: 30,
          bucket_size_in_seconds: 5,
        }
        conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2
        conn.options[:open_timeout] = open_timeout # seconds
        conn.options[:timeout] = timeout # seconds
        conn.adapter :persistent_excon
      end
    end

    def self.entity_type_for(entity)
      # Organizations are a subset of Users
      if entity.is_a?(User)
        :ENTITY_TYPE_USER
      elsif entity.is_a?(Business)
        :ENTITY_TYPE_BUSINESS
      else
        :ENTITY_TYPE_INVALID
      end
    end

    def self.retry_block(timeout:)
      proc do |env, _, _, exception|
        # use monotonic clock when calculating elapsed time to account for clock changes
        env[:retry_started_at] ||= Process.clock_gettime(Process::CLOCK_MONOTONIC)
        now = Process.clock_gettime(Process::CLOCK_MONOTONIC)
        raise StandardError.new("request timed out") if now - env[:retry_started_at] >= timeout

        tags = [
          "status:#{env[:status]}",
          "method:#{env[:method]}",
          "path:#{env[:url].request_uri}",
          "error:#{exception.class}",
        ]
        GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries", tags: tags)
      end
    end
  end
end
