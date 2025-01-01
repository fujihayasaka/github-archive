# frozen_string_literal: true

require "aqueduct"
require "aqueduct/worker"
require_relative "../job_queues"

# This file was heavily inspired by https://github.com/github/meuse/blob/main/lib/meuse/config/aqueduct_config.rb
module DependencyGraph
  module Aqueduct
    EnqueueError = Class.new(StandardError)

    class AqueductConfig
      CLIENT_ERRORS = [::Aqueduct::Client::ClientError, ::Aqueduct::Client::RequestError].freeze

      # Values ported from GitHub
      # We should tune these empirically
      DEFAULT_REDELIVERY_TIMEOUT_SECONDS = 45
      DEFAULT_REDELIVERY_ATTEMPTS = 3
      DEFAULT_HEARTBEAT_INTERVAL_SECONDS = DEFAULT_REDELIVERY_TIMEOUT_SECONDS / 3
      DEFAULT_HEARTBEAT_CHECK_INTERVAL_SECONDS = 6.seconds

      def initialize(api_key: nil, api_key_version: nil, send_hmac_secret: nil, receive_hmac_secrets: nil)
        @api_key = api_key
        @api_key_version = api_key_version
        @send_hmac_secret = send_hmac_secret
        # Multiple secrets are stored in the key as space separated
        # values.
        @receive_hmac_secrets = receive_hmac_secrets.try(:split, " ")
      end

      def app_name
        Rails.configuration.aqueduct_app_name
      end

      def queue_job(
        queue:,
        payload:,
        redelivery_timeout_secs: DEFAULT_REDELIVERY_TIMEOUT_SECONDS,
        max_redelivery_attempts: DEFAULT_REDELIVERY_ATTEMPTS,
        deliver_at: nil
      )
        client.send_job(
          queue: queue,
          payload: payload,
          redelivery_timeout_secs: redelivery_timeout_secs,
          max_redelivery_attempts: max_redelivery_attempts,
          deliver_at: deliver_at,
        )
      rescue *CLIENT_ERRORS => e
        raise DependencyGraph::Aqueduct::EnqueueError, extract_aqueduct_client_message(e)
      end

      # This method is a handler for Aqueduct's worker implementation, it's called whenever a job is dequeued.
      # You can see where this is wired up by checking this block in config/initializers/aqueduct.rb:
      #   Aqueduct::Worker.configure do |config|
      def work_job(job, status)
        # Deserializes a "Normal" serialized rails ActiveJob and runs it. You can create these easily by doing
        #  <JobClass>.new.serialize

        payload = JSON.parse(job.payload)
        job_class = payload["job_class"]
        raise "payload must contain job class" if job_class.nil?

        ActiveJob::Base.execute payload

        Instrument.increment("aqueduct.job_performed", job: job_class)
      rescue StandardError => e
        status.failed!(e)
        DependencyGraph.logger.error("aqueduct job error", e)
        raise e
      end

      def extract_aqueduct_client_message(error)
        "metadata: #{error.metadata}, inner_error: #{error}#{error.cause.nil? ? "" : (", error_cause: " + error.cause.message)}"
      end

      def queues
        ["service-to-service"].concat(DependencyGraphAPI::JobQueues.get_prefixed_queues)
      end

      def client
        @client ||= ::Aqueduct::Client.new(
          api_key: @api_key,
          api_key_version: @api_key_version,
          send_hmac_secret: @send_hmac_secret,
          receive_hmac_secrets: @receive_hmac_secrets,
          send_retries: 3,
        ) do |conn|
          conn.use GitHub::FaradayMiddleware::RequestID
          conn.use GitHub::FaradayMiddleware::Datadog, stats: Rails.application.stats, service_name: "aqueduct"

          conn.adapter :excon
        end
      end

      def heartbeat_interval_seconds
        DEFAULT_HEARTBEAT_INTERVAL_SECONDS
      end

      def heartbeat_check_interval_seconds
        DEFAULT_HEARTBEAT_CHECK_INTERVAL_SECONDS
      end
    end
  end
end
