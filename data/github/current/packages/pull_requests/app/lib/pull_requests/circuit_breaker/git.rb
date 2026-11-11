# typed: strict
# frozen_string_literal: true

require "resilient/circuit_breaker"

module PullRequests
  module CircuitBreaker
    module Git
      include Kernel

      # Infrastructure errors that indicate platform-wide Git service degradation.
      # Aligned with PullRequests::GitSystems.classify_exception timeout/outage classifications.
      INFRASTRUCTURE_ERRORS = T.let([
        Faraday::ConnectionFailed,
        Faraday::TimeoutError,
        ::Git::Ref::UpdateFailedSensitive,
        GitHub::DGit::InsufficientQuorumError,
        GitHub::DGit::ThreepcBusyError,
        GitHub::DGit::ThreepcError,
        GitHub::DGit::ThreepcFailedToLock,
        GitHub::DGit::UnroutedError,
        GitHub::Spokes::ClientError,
        GitRPC::CommandBusy,
        GitRPC::ConnectionError,
        GitRPC::Error,
        GitRPC::NetworkError,
        GitRPC::Timeout,
        GitRPC::Protocol::DGit::ResponseError,
        OpenSSL::SSL::SSLErrorWaitReadable,
        SpokesAPI::Canceled,
        SpokesAPI::ResourceExhausted,
        SpokesAPI::TimedOut,
        SpokesAPI::TwirpConnectionError,
        SpokesAPI::TwirpServerError,
        Timeout::Error,
      ].freeze, T::Array[T.class_of(StandardError)])

      DEFAULT_CIRCUIT_BREAKER_CONFIG = T.let({
        error_threshold_percentage: 0.1,
        request_volume_threshold: 5,
        window_size_in_seconds: 60,
        bucket_size_in_seconds: 10,
        sleep_window_seconds: 5,
      }.freeze, T::Hash[Symbol, Numeric])

      MetricContext = T.type_alias do
        {
          rpc: Symbol,
          repository_id: T.nilable(Integer),
          pull_request_id: T.nilable(Integer),
          circuit_key: String,
          tags: T::Array[String],
        }
      end

      sig do
        type_parameters(:T).params(
          rpc_method: Symbol,
          repository_id: T.nilable(Integer),
          pull_request_id: T.nilable(Integer),
          block: T.proc.returns(T.type_parameter(:T)),
        ).returns(T.type_parameter(:T))
      end
      def with_git_circuit_breaker(rpc_method, repository_id, pull_request_id, &block)
        return yield unless FeatureFlag.vexi.enabled?(:pull_requests_git_circuit_breaker, "Repository:#{repository_id}", default: false)

        return yield unless repository_id
        return yield unless pull_request_id

        circuit_key_prefix = "pull_requests.git.#{rpc_method}"
        circuit = circuit_breaker_for(circuit_key_prefix, rpc_method, repository_id)

        context = build_context(
          rpc: rpc_method,
          repository_id: repository_id,
          pull_request_id: pull_request_id,
          circuit_key: circuit.key.name
        )

        track_request(context)

        circuit_was_open = !circuit.allow_request?
        if circuit_was_open
          handle_circuit_open(context)
        end

        result = T.let(nil, T.untyped)

        begin
          result = yield
        rescue *INFRASTRUCTURE_ERRORS => e
          exception = e
        end

        start_time = Time.now

        case exception
        when nil
          circuit.success
          track_recovery(context) if circuit_was_open
          track_success(context, start_time)

          result
        else
          circuit.failure
          track_failure(context, exception, start_time, circuit.metrics.error_percentage)
          raise exception
        end
      end

      sig { params(circuit_key_prefix: String, rpc_method: Symbol, repository_id: T.nilable(Integer)).returns(Resilient::CircuitBreaker) }
      def circuit_breaker_for(circuit_key_prefix, rpc_method, repository_id)
        config = circuit_breaker_config_for_rpc(rpc_method, repository_id)
        config_hash = Digest::MD5.hexdigest(config.to_s)[0..7] # rubocop:disable GitHub/InsecureHashAlgorithm
        circuit_key = "#{circuit_key_prefix}_#{config_hash}"
        Resilient::CircuitBreaker.get(circuit_key, config)
      end

      protected

      sig { params(context: MetricContext).void }
      def track_recovery(context)
        GitHub.dogstats.increment(
          "pull_requests.git.circuit_breaker.recovered",
          tags: context[:tags]
        )

        GitHub.logger.info(
          "pull_requests.git.circuit_breaker.event": "circuit_recovered",
          "pull_requests.git.circuit_breaker.key": context[:circuit_key],
          "gh.git.rpc": context[:rpc],
          "gh.repo.id": context[:repository_id],
          "gh.pull_request.id": context[:pull_request_id],
        )
      end

      sig { params(context: MetricContext).void }
      def handle_circuit_open(context)
        GitHub.dogstats.increment("pull_requests.git.circuit_breaker.open", tags: context[:tags])

        GitHub.logger.info(
          "pull_requests.git.circuit_breaker.event": "circuit_open",
          "pull_requests.git.circuit_breaker.key": context[:circuit_key],
          "gh.git.rpc": context[:rpc],
          "gh.repo.id": context[:repository_id],
          "gh.pull_request.id": context[:pull_request_id],
        )
      end

      sig { params(context: MetricContext).void }
      def track_request(context)
        GitHub.dogstats.increment(
          "pull_requests.git.circuit_breaker.request",
          tags: context[:tags]
        )
      end

      sig { params(context: MetricContext, start_time: Time).void }
      def track_success(context, start_time)
        GitHub.dogstats.increment(
          "pull_requests.git.circuit_breaker.success",
          tags: context[:tags]
        )
        GitHub.dogstats.distribution_timing_since(
          "pull_requests.git.circuit_breaker.duration",
          start_time,
          tags: context[:tags] + ["status:success"]
        )
      end

      sig { params(context: MetricContext, error: Exception, start_time: Time, error_percentage: T.nilable(Integer)).void }
      def track_failure(context, error, start_time, error_percentage)
        GitHub.dogstats.increment(
          "pull_requests.git.circuit_breaker.failure",
          tags: context[:tags] + ["error_type:#{error.class.name}"]
        )
        GitHub.dogstats.distribution_timing_since(
          "pull_requests.git.circuit_breaker.duration",
          start_time,
          tags: context[:tags] + ["status:failure"]
        )

        log_data = {
          "pull_requests.git.circuit_breaker.event": "infrastructure_failure",
          "gh.git.rpc": context[:rpc],
          "gh.repo.id": context[:repository_id],
          "gh.pull_request.id": context[:pull_request_id],
          "gh.error.class": error.class.name,
          "gh.error.message": error.message,
          "gh.error.percentage": error_percentage,
        }

        GitHub.logger.warn(log_data)
      end

      sig { params(rpc_method: Symbol, repository_id: T.nilable(Integer)).returns(T::Hash[Symbol, Numeric]) }
      def circuit_breaker_config_for_rpc(rpc_method, repository_id)
        scoped_to_repo = repository_id && FeatureFlag.vexi.enabled?(:pr_git_circuit_breaker_by_repo, "Repository:#{repository_id}", default: false)
        suffix = scoped_to_repo ? "_#{repository_id}" : ""

        DEFAULT_CIRCUIT_BREAKER_CONFIG.each_with_object({}) do |(config_field, default_config_value), hash|
          flag_name = "pull_request_#{rpc_method}_#{config_field}_git_circuit_breaker#{suffix}"
          value = FeatureFlag.vexi.percentage_of_actors_value_or_raise(flag_name) # rubocop:disable GitHub/FeatureManagement/NoVexiNonStandardUsage
          stored_config_value =
            if config_field == :error_threshold_percentage
              value / 100
            else
              value.to_i
            end
          if stored_config_value > 0
            hash[config_field] = stored_config_value
          else
            hash[config_field] = default_config_value
          end
        end
      rescue => e
        GitHub.logger.warn("circuit_breaker_config_for_rpc failed: #{e.message}")
        DEFAULT_CIRCUIT_BREAKER_CONFIG
      end

      private

      sig do
        params(
          rpc: Symbol,
          repository_id: T.nilable(Integer),
          pull_request_id: T.nilable(Integer),
          circuit_key: String
        ).returns(MetricContext)
      end
      def build_context(rpc:, repository_id:, pull_request_id:, circuit_key:)
        {
          rpc: rpc,
          repository_id: repository_id,
          pull_request_id: pull_request_id,
          circuit_key: circuit_key,
          tags: tags(rpc, repository_id),
        }
      end

      sig { params(rpc: Symbol, repository_id: T.nilable(Integer)).returns(T::Array[String]) }
      def tags(rpc, repository_id)
        tags = ["rpc:#{rpc}"]

        if FeatureFlag.vexi.enabled?(:spokesd_spec_tagged_metrics, "Repository:#{repository_id}", default: false)
          tags << "repo_id:#{repository_id}"
        end

        tags
      end
    end
  end
end
