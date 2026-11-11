# typed: strict
# frozen_string_literal: true

require "net/http/persistent"
require "exp_tas_client"

module AzureEXP
  module V2
    module Experiments
      # HTTP client for the Treatment Assignment Service (TAS).
      #
      # Wraps the auto-generated `exp-tas-client` gem with:
      # - Persistent HTTP connections via Net::HTTP::Persistent
      # - Circuit breaker via GitHub::FaradayMiddleware::Resilient
      # - Hard timeout (configurable, default 50ms)
      # - Exponential backoff when breaker is open
      # - Failbot reporting on unexpected errors
      # - dogstats metrics on every call
      # - Never raises: returns AssignmentResult.empty on any failure
      #
      # The exp-tas-client gem builds its own Faraday connection, so we cannot
      # pass a GitHub::FaradayClient::Internal instance directly (the gem has
      # no hook to accept an external connection). Instead we configure the
      # gem's connection and manually add the same RequestID and TenantContext
      # middleware that FaradayClient::Internal injects, so internal
      # service-to-service calls stay traceable and tenant-scoped. See
      # lib/github/faraday_client/internal.rb for the reference stack.
      #
      class Client
        extend T::Helpers

        SERVICE_NAME = "monolith.experiments"
        DEFAULT_TIMEOUT = 0.05 # 50ms hard timeout
        DEFAULT_OPEN_TIMEOUT = 0.025 # 25ms connection open timeout

        sig { void }
        def initialize
          @api = T.let(build_api, ExpTasClient::DefaultApi)
        end

        # Calls TAS with the given userParams and returns an AssignmentResult.
        # Never raises. On any failure, returns AssignmentResult.empty.
        sig do
          params(
            user_params: T::Hash[String, String],
            scopes: T.nilable(T::Array[String]),
            required_variants: T.nilable(T::Array[String]),
            blocked_variants: T.nilable(T::Array[String]),
          ).returns(AzureEXP::V2::Experiments::AssignmentResult)
        end
        def get_assignment(user_params, scopes: nil, required_variants: nil, blocked_variants: nil)
          return empty_with_metric("empty_parameters") if user_params.empty?

          request = ExpTasClient::AssignmentRequest.new(
            user_params: user_params,
            scopes: scopes,
            required_variants: required_variants&.reject(&:empty?),
            blocked_variants: blocked_variants&.reject(&:empty?),
          )

          start = T.let(GitHub::Dogstats.monotonic_time, T.nilable(Float))
          response = @api.get_treatment_assignment(request)
          emit_latency(start, error: false)

          if response
            AzureEXP::V2::Experiments::AssignmentResult.new(
              feature_variables: response.feature_variables || {},
              assignment_context: response.assignment_context || "",
              data_version: response.data_version || 0,
            )
          else
            empty_with_metric("nil_response")
          end
        rescue ExpTasClient::ApiError => e
          emit_latency(start, error: true, reason: "api_error")
          GitHub.dogstats.increment(
            "monolith.experiments.assignment.error",
            tags: ["reason:api_error", "status:#{e.code}"],
          )
          Failbot.report(e) if e.code.to_i >= 500
          AzureEXP::V2::Experiments::AssignmentResult.empty
        rescue Faraday::TimeoutError
          emit_latency(start, error: true, reason: "timeout")
          GitHub.dogstats.increment(
            "monolith.experiments.assignment.error",
            tags: ["reason:timeout"],
          )
          AzureEXP::V2::Experiments::AssignmentResult.empty
        rescue Faraday::ConnectionFailed
          emit_latency(start, error: true, reason: "connection_failed")
          GitHub.dogstats.increment(
            "monolith.experiments.assignment.error",
            tags: ["reason:connection_failed"],
          )
          AzureEXP::V2::Experiments::AssignmentResult.empty
        rescue StandardError => e
          emit_latency(start, error: true, reason: "unexpected")
          GitHub.dogstats.increment(
            "monolith.experiments.assignment.error",
            tags: ["reason:unexpected"],
          )
          Failbot.report(e)
          AzureEXP::V2::Experiments::AssignmentResult.empty
        end

        private

        sig { returns(ExpTasClient::DefaultApi) }
        def build_api
          config = ExpTasClient::Configuration.new do |c|
            c.scheme = GitHub.azure_experiments_v2_tas_scheme
            c.host = GitHub.azure_experiments_v2_tas_host
          end

          config.configure_faraday_connection do |conn|
            # Mirror the middleware GitHub::FaradayClient::Internal injects for
            # internal service-to-service calls. The exp-tas-client gem owns
            # this connection so we can't use Internal directly; keep these in
            # sync with lib/github/faraday_client/internal.rb.
            conn.use ::GitHub::FaradayMiddleware::RequestID
            conn.use ::GitHub::FaradayMiddleware::TenantContext

            conn.options[:open_timeout] = DEFAULT_OPEN_TIMEOUT
            conn.options[:timeout] = DEFAULT_TIMEOUT

            conn.use ::GitHub::FaradayMiddleware::Resilient, name: SERVICE_NAME, options: {
              instrumenter: GitHub,
              sleep_window_seconds: 10,
              request_volume_threshold: GitHub.azure_experiments_v2_resilient_request_volume_threshold,
              error_threshold_percentage: GitHub.azure_experiments_v2_resilient_error_threshold_percentage,
              window_size_in_seconds: 30,
              bucket_size_in_seconds: 5,
            }
            conn.adapter :net_http_persistent
          end

          ExpTasClient::DefaultApi.new(ExpTasClient::ApiClient.new(config))
        end

        sig { params(reason: String).returns(AzureEXP::V2::Experiments::AssignmentResult) }
        def empty_with_metric(reason)
          GitHub.dogstats.increment(
            "monolith.experiments.assignment.error",
            tags: ["reason:#{reason}"],
          )
          AzureEXP::V2::Experiments::AssignmentResult.empty
        end

        # Fires the assignment latency distribution. Emitted on every call,
        # success or failure, so timeouts and errors show up in latency
        # dashboards. Failure calls carry an error_reason tag. Skips emission
        # if the timer never started (the call raised before the request).
        sig { params(start: T.nilable(Float), error: T::Boolean, reason: T.nilable(String)).void }
        def emit_latency(start, error:, reason: nil)
          return if start.nil?

          tags = ["error:#{error}"]
          tags << "error_reason:#{reason}" if reason

          GitHub.dogstats.distribution(
            "monolith.experiments.assignment.latency_ms",
            GitHub::Dogstats.duration(start),
            tags: tags,
          )
        end
      end
    end
  end
end
