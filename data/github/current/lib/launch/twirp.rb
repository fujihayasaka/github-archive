# typed: true
# frozen_string_literal: true

module Launch
  module Twirp

    autoload :BaseClient, "launch/twirp/base_client"
    autoload :NullClient, "launch/twirp/null_client"

    autoload :ArtifactsExchangeClient, "launch/twirp/artifacts_exchange_client"
    autoload :ArtifactsExchangeLabClient, "launch/twirp/artifacts_exchange_lab_client"
    autoload :CacheClient, "launch/twirp/cache_client"
    autoload :ChecksClient, "launch/twirp/checks_client"
    autoload :ChecksLabClient, "launch/twirp/checks_lab_client"
    autoload :DeployerClient, "launch/twirp/deployer_client"
    autoload :DeployerLabClient, "launch/twirp/deployer_lab_client"
    autoload :EnvironmentClient, "launch/twirp/environment_client"
    autoload :EnvironmentLabClient, "launch/twirp/environment_lab_client"
    autoload :LargerRunnersClient, "launch/twirp/larger_runners_client"
    autoload :SelfHostedRunnersClient, "launch/twirp/self_hosted_runners_client"
    autoload :RunnerGroupsClient, "launch/twirp/runner_groups_client"
    autoload :RunnerScaleSetsClient, "launch/twirp/runner_scale_sets_client"

    class BaseError < StandardError; attr_accessor :msg; end
    class Error < BaseError; end
    class ServiceUnavailableError < BaseError; end

    sig { returns(ArtifactsExchangeClient) }
    def self.artifacts_exchange_client
      @artifacts_exchange_client ||= ArtifactsExchangeClient.new
    end

    sig { returns(ArtifactsExchangeLabClient) }
    def self.artifacts_exchange_lab_client
      @artifacts_exchange_lab_client ||= ArtifactsExchangeLabClient.new
    end

    # In production GitHub we can see workflow executions from both production and lab Actions app.
    # Artifacts must be requested from appropriate Actions app which created the related check suite, otherwise they will not be found.
    #
    # Returns the Artifacts Exchange Twirp client for the appropriate Actions app
    sig { params(check_suite: CheckSuite).returns(Launch::Twirp::ArtifactsExchangeClient) }
    def self.artifacts_exchange_client_for_check_suite(check_suite)
      raise ArgumentError.new("check_suite must have been created by a GitHub App") if check_suite.present? && check_suite.github_app.ghost?
      if check_suite.present? && check_suite.github_app.launch_lab_github_app?
        artifacts_exchange_lab_client
      else
        artifacts_exchange_client
      end
    end

    sig { returns(CacheClient) }
    def self.cache_client
      @cache_client ||= CacheClient.new
    end

    sig { params(lab: T::Boolean).returns(ChecksClient) }
    def self.checks_client(lab: false)
      if lab
        @checks_lab_client ||= ChecksLabClient.new
      else
        @checks_client ||= ChecksClient.new
      end
    end

    sig { returns(DeployerClient) }
    def self.deployer_client
      @deployer_client ||= DeployerClient.new
    end

    sig { returns(DeployerLabClient) }
    def self.deployer_lab_client
      @deployer_lab_client ||= DeployerLabClient.new
    end

    sig { returns(EnvironmentClient) }
    def self.environment_client
      @environment_client ||= EnvironmentClient.new
    end

    sig { returns(EnvironmentLabClient) }
    def self.environment_lab_client
      @environment_lab_client ||= EnvironmentLabClient.new
    end

    sig { returns(LargerRunnersClient) }
    def self.larger_runners_client
      @larger_runners_client ||= LargerRunnersClient.new(retry_options: retry_options)
    end

    sig { returns(SelfHostedRunnersClient) }
    def self.self_hosted_runners_client
      @self_hosted_runners_client ||= SelfHostedRunnersClient.new(retry_options: retry_options)
    end

    sig { returns(RunnerGroupsClient) }
    def self.runner_groups_client
      @runner_groups_client ||= RunnerGroupsClient.new(retry_options: retry_options)
    end

    sig { returns(RunnerScaleSetsClient) }
    def self.runner_scale_sets_client
      @runner_scale_sets_client ||= RunnerScaleSetsClient.new(retry_options: retry_options)
    end

    def self.retry_options
      return nil unless FeatureFlag.vexi.enabled?(:retry_actions_clients, default: false)
      {
        max:                 3,
        interval:            0.050,
        interval_randomness: 0.5,
        backoff_factor:      1.2,
        retry_statuses: [429, 502, 503, 504],
        # In Twirp, everything is a POST
        methods:     [:post],
        exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError, Faraday::ServerError],
      }
    end
  end
end
