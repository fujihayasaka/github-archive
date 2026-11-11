# typed: true
# frozen_string_literal: true

require "gitbackups/gitbackups_pb"
require "gitbackups/gitbackups_twirp"

module GitHub
  module Gitbackups
    SERVICE_NAME = "gitbackupsd"

    class Client
      # Public: delete a repository from backups
      #
      # Note that no checks are performed against the legal hold statuses. This must
      # only be called after checking there.
      #
      # Returns: nothing
      def delete(spec)
        req = GitHub::GitBackups::V1::DeleteRequest.new(spec: spec)

        begin
          resp = client.delete req
          if resp.error
            return :not_found if resp.error.msg == "not found"

            # Twirp Errors are not exceptions, so wrap it on our own interpretation
            raise ClientError.new(resp.error.to_s)
          end
        rescue ClientError, Faraday::Error => e
          GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.errors", tags: ["type:#{e.class.name}"])
          raise
        end

        :ok
      end

      def schedule_maintenance(specs)
        req = GitHub::GitBackups::V1::MaintenanceRequest.new(specs: specs)

        begin
          resp = client.schedule_maintenance(req)
          raise ClientError.new(resp.error.to_s) if resp.error
        rescue ClientError, Faraday::Error => e
          GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.errors", tags: ["type:#{e.class.name}"])
          raise
        end
      end

      def status(spec)
        req = GitHub::GitBackups::V1::StatusRequest.new(spec: spec)

        begin
          resp = client.status(req)
          raise ClientError.new(resp.error.to_s) if resp.error
        rescue ClientError, Faraday::Error => e
          GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.errors", tags: ["type:#{e.class.name}"])
          raise
        end
        resp.data
      end

      def client
        @client ||= build_client
      end

      def build_client
        conn = ::Faraday.new(GitHub.gitbackupsd_url) do |conn|
          conn.options[:open_timeout] = 0.250
          conn.options[:timeout]      = 4.0
          conn.headers[:user_agent]   = "GitHub::Gitbackups::Client github-#{GitHub.role} (#{GitHub.current_sha})"

          conn.request :retry,
            max:                 3,
            interval:            0.050,
            interval_randomness: 0.5,
            backoff_factor:      1.2,

            # What methods should faraday attempt a retry?
            # In Twirp, everything is a POST...
            methods:     [:post],
            exceptions:  [Faraday::ConnectionFailed, Faraday::RetriableResponse, Faraday::TimeoutError],
            retry_block: proc { GitHub.dogstats.increment("rpc.#{SERVICE_NAME}.retries") }

          conn.use ::GitHub::FaradayMiddleware::RequestID
          conn.use ::GitHub::FaradayMiddleware::Datadog, stats: GitHub.dogstats, service_name: SERVICE_NAME
          conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME
          conn.use ::GitHub::FaradayMiddleware::IncreasingTimeout,
            factor: 2

          conn.adapter :typhoeus
        end

        GitHub::GitBackups::V1::GitbackupsClient.new(conn)
      end
    end
  end
end
