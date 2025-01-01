# typed: true
# frozen_string_literal: true

require "turboghas"
require "github/faraday_adapter/persistent_excon"

class ::Turboghas::Proto::GetEnabledRepositoriesResponse::Repository
  def name_with_display_owner
    owner, _, name = nwo.partition("/") # rubocop:disable GitHub/DoNotAllowNameWithOwner
    "#{ User.to_display_login(owner) }/#{ name }"
  end
end

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

    # SKU represents a billing SKU and a collection of advanced security features
    # the billing sku is where we send the number of active committers (pro-rated over the month)
    # active committers are calculated by counting the number of unique committers in the last 90 days to repositories
    # where any of the features in the features list are enabled
    class SKU < T::Enum
      enums do
        Bundled = new
        CodeSecurity = new
        SecretSecurity = new
      end

      sig { returns(String) }
      def to_param
        case self
        when Bundled then "bundled"
        when CodeSecurity then "code-security"
        when SecretSecurity then "secret-protection"
        end
      end

      sig { params(param: T.nilable(String)).returns(GitHub::Turboghas::SKU) }
      def self.from_param(param)
        case param&.dasherize
        when "code-security"
          CodeSecurity
        when "secret-protection"
          SecretSecurity
        else
          Bundled
        end
      end

      sig { returns(T::Array[Integer]) }
      def features
        case self
        when Bundled then [MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_ALL]
        when CodeSecurity then [MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_CODE_SCANNING]
        when SecretSecurity then [MonolithTwirp::CodeScanning::Turboghas::V1::Feature::FEATURE_SECRET_SCANNING]
        end
      end

      sig { returns(T::Hash[Symbol, T.untyped]) }
      def to_proto
        sku = (
          case self
          when Bundled then MonolithTwirp::CodeScanning::Turboghas::V1::SKU::SKU_GHAS_LICENSES
          when CodeSecurity then MonolithTwirp::CodeScanning::Turboghas::V1::SKU::SKU_GHAS_CODE_SECURITY_LICENSES
          when SecretSecurity then MonolithTwirp::CodeScanning::Turboghas::V1::SKU::SKU_GHAS_SECRET_PROTECTION_LICENSES
          end
        )
        { features:, sku: }
      end

      sig { returns(String) }
      def title
        case self
        when Bundled then "GitHub Advanced Security"
        when CodeSecurity then "Code Security"
        when SecretSecurity then "Secret Protection"
        end
      end

      sig { returns(String) }
      def emission_sku
        case self
        when Bundled then "ghas_licenses"
        when CodeSecurity then "ghas_code_security_licenses"
        when SecretSecurity then "ghas_secret_protection_licenses"
        end
      end
    end

    class ResponseError < StandardError
      attr_reader :error
      def initialize(error)
        @error = error
        super(error)
      end
    end

    sig do
      type_parameters(:U).
      params(response: Twirp::ClientResp[T.type_parameter(:U)]).
      returns(T.type_parameter(:U))
    end
    def self.check_error(response)
      error = response.error
      unless error.nil?
        e = ::GitHub::Turboghas::ResponseError.new(error.msg)
        Failbot.report(e, catalog_service: "github/advanced_security_billing")
        raise e
      end
      response.data
    end

    def self.content_type
      return "application/json" if Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
      "application/protobuf"
    end

    sig { params(connection: T.any(String, Faraday::Connection)).returns(::Turboghas::Proto::AdvancedSecurityAPIClient) }
    def self.new_client(connection:)
      ::Turboghas::Proto::AdvancedSecurityAPIClient.new(connection, { content_type: content_type })
    end

    sig { returns(::Turboghas::Proto::AdvancedSecurityAPIClient) }
    def self.client
      @client ||= new_client(connection: connection)
    end

    sig { returns(::Turboghas::Proto::AdvancedSecurityAPIClient) }
    def self.async_client
      @async_client ||= new_client(connection: connection(async: true))
    end

    sig { params(async: T::Boolean, timeout: Integer, open_timeout: Integer).returns(Faraday::Connection) }
    def self.connection(async: false, timeout: 5, open_timeout: 1)
      (async ? ConcurrentFaraday : GitHub::FaradayClient::Internal).new(url: GitHub.turboghas_url) do |conn|
        conn.use GitHub::FaradayMiddleware::Staffbar, url: GitHub.turboghas_url
        conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: GitHub.turboghas_hmac_key
        conn.use GitHub::FaradayMiddleware::RequestID
        conn.use GitHub::FaradayMiddleware::TenantContext
        conn.use (async ? ::GitHub::FaradayMiddleware::DatadogAsync : ::GitHub::FaradayMiddleware::Datadog),
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
