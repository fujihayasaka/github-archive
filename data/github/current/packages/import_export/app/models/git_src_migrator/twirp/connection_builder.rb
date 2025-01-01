# typed: true
# frozen_string_literal: true

module GitSrcMigrator
  module Twirp
    class ConnectionBuilder
      SERVICE_NAME = "git_src_migrator_api"

      attr_reader :url, :hmac_key

      # Construct a ConnectionBuilder.  Configure for staging if import_export_gitops_on_actions_use_staging feature
      # flag is set or for review lab if import_export_gitops_on_actions_use_review_lab feature flag is set.
      #
      # @param [Organization, User] ower Organization or User to check for import_export_gitops_on_actions_use_staging
      #   or import_export_gitops_on_actions_use_review_lab feature flag.
      # @return [ConnectionBuilder] ConnectionBuilder instance.
      def self.for_owner(owner)
        return self.staging if GitHub.flipper[:import_export_gitops_on_actions_use_staging].enabled?(owner)
        return self.review_lab if GitHub.flipper[:import_export_gitops_on_actions_use_review_lab].enabled?(owner)

        self.new
      end

      # Construct a ConnectionBuilder configured for staging.
      #
      # @return [ConnectionBuilder] ConnectionBuilder instance.
      def self.staging
        self.new(url: GitHub.git_src_migrator_staging_url, hmac_key: GitHub.git_src_migrator_staging_hmac_key)
      end

      # Construct a ConnectionBuilder configured for review lab.
      #
      # @return [ConnectionBuilder] ConnectionBuilder instance.
      def self.review_lab
        self.new(url: GitHub.git_src_migrator_review_lab_url, hmac_key: GitHub.git_src_migrator_review_lab_hmac_key)
      end

      # Proc called when retries occur.
      #
      # @return [Proc] Proc to be called during retries.
      def self.retry_proc
        proc do |env, _, _retries, exception|
          tags = [
            "status:#{env[:status]}",
            "method:#{env[:method]}",
            "path:#{env[:url].request_uri}",
            "error:#{exception.class}",
          ]

          GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries", tags: tags)
        end
      end

      # Construct a ConnectionBuilder.
      #
      # @param [String] url Twirp API URL for GitHub Source Migrator.
      # @param [String] hmac_key Client HMAC key for authenticating to the GSM Twirp API.
      # @return [void]
      def initialize(url: GitHub.git_src_migrator_url, hmac_key: GitHub.git_src_migrator_hmac_key)
        @url = url
        @hmac_key = hmac_key
      end

      # Construct a GitHub::FaradayClient::Internal instance used to make requests to GitHub Source Migrator.
      #
      # @return [GitHub::FaradayClient::Internal] Connector used for GSM requests.
      def build
        GitHub::FaradayClient::Internal.new(url: url) do |conn|
          conn.options[:open_timeout] = 0.250
          conn.headers[:user_agent]   = "github-#{GitHub.role}/#{GitHub.current_sha}"

          conn.request :retry, {
            max:                 3,
            interval:            0.050,
            interval_randomness: 0.5,
            backoff_factor:      1.2,

            # What methods should faraday attempt a retry?
            # In Twirp, everything is a POST...
            methods:     [:post],
            exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
            retry_block: self.class.retry_proc
          }

          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::HMACAuth, hmac_key: hmac_key
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, tracked_availability_slos: ["git_src_migrator_twirp_api"]
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2

          conn.adapter :typhoeus
        end
      end
    end
  end
end
