# typed: true
# frozen_string_literal: true

require "monolith-twirp-octoshift-migrations"

module Octoshift
  module Twirp
    class ConnectionBuilder
      SERVICE_NAME = "octoshift_api"

      attr_reader :url, :hmac_key

      def self.for_organization(organization)
        if organization.name == "octoshift-review-lab"
          self.review_lab
        elsif organization.name == "octoshift-load-testing"
          self.load_testing
        elsif GitHub.flipper[:octoshift_use_staging].enabled?(organization)
          self.staging
        else
          self.new
        end
      end

      def self.for_enterprise(enterprise)
        if enterprise.slug == "teenyverse"
          self.review_lab
        elsif GitHub.flipper[:octoshift_use_staging].enabled?(enterprise)
          self.staging
        else
          self.new
        end
      end

      def self.staging
        self.new(url: GitHub.octoshift_staging_url, hmac_key: GitHub.octoshift_staging_hmac_key)
      end

      def self.review_lab
        self.new(url: GitHub.octoshift_review_lab_url, hmac_key: GitHub.octoshift_review_lab_hmac_key)
      end

      def self.load_testing
        self.new(url: GitHub.octoshift_load_testing_url, hmac_key: GitHub.octoshift_load_testing_hmac_key)
      end

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

      # Public: Construct a Twirp connection factory.
      #
      # url - The internal Twirp API URL, as a String.
      # hmac_key - The client HMAC key, as a String.
      def initialize(url: GitHub.octoshift_url, hmac_key: GitHub.octoshift_hmac_key)
        @url = url
        @hmac_key = hmac_key
      end

      # Public: Build a Faraday::Connection instance.
      def build
        GitHub::FaradayClient::Internal.new(url: url) do |conn|
          conn.options[:open_timeout] = 1
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
          conn.use GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME, tracked_availability_slos: ["octoshift_twirp_api"]
          conn.use GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
          conn.use GitHub::FaradayMiddleware::IncreasingTimeout, factor: 2

          conn.adapter :typhoeus
        end
      end
    end
  end
end
