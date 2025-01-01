# typed: false
# frozen_string_literal: true

require "hydro"
require "hydro/circuit_breaking_sink"
require "hydro/cutover_sink"
require "hydro/datadog_reporter"
require "hydro/dirty_exit"
require "hydro/fallback_sink"
require "hydro/instrumenter"
require "resolv"

autoload "HydroAggregationApi", "hydro_aggregation_api/client"

module GitHub
  module Config
    module HydroConfig
      MAX_SHUTDOWN_TIME = 15

      DEVELOPMENT_BROKER = "127.0.0.1:9092"

      DEFAULT_HEADERS_PROC = proc do
        headers = { "replication_state" => DatabaseSelector::ReplicationState.current&.to_hash&.to_json }.compact
        if GitHub.multi_tenant_enterprise? && (current_tenant = GitHub::CurrentTenant.get)
          headers["X-GitHub-Tenant-ID"] = current_tenant.id.to_s
          headers["X-GitHub-Tenant"] = current_tenant.slug
        end
        headers
      end

      # For use as a guard with the hydro initializer.
      #
      # During a constrained boot (timerd, git hooks) the initializer is
      # required directly from `rock_queue.rb` since RockQueue needs hydro
      # publishing to be available and configured. However, during a normal full
      # boot, the initializer is loaded twice: once when required directly by
      # `rock_queue.rb`, and again via the regular rails initializer process.
      # This guard prevents the second load from trying to reload hydro schemas
      # or reinitialize the datadog reporting.
      attr_writer :hydro_initialized

      def hydro_initialized?
        @hydro_initialized
      end

      def hydro_logger
        @hydro_logger ||= GitHub::Telemetry::Logs.logger("GitHub::Config::HydroConfig")
      end

      # Is publishing to Hydro enabled?
      #
      # It's not necessary or desirable to check this method before publishing to
      # Hydro. GitHub.hydro_publisher will always return a valid publisher that
      # will route messages to the correct place based on the environment.
      def hydro_enabled?
        return true if GitHub::AppEnvironment.production? # always enabled in production!
        return false if %w[1 true].include? GitHub.environment.fetch("DISABLE_HYDRO_DURING_BOOTSTRAP", "0")

        true
      end

      # HMAC key for authenticating hydro browser payloads.
      attr_accessor :hydro_browser_payload_secret

      def hydro_client
        HydroLoader.load_github if GitHub.lazy_load_hydro?
        @hydro_client ||= Hydro::Client.new(environment: GitHub::AppEnvironment.env)
      end

      def hydro_sink_initialized?
        defined?(@hydro_publisher) || defined?(@sync_hydro_publisher)
      end

      def hydro_site
        return "unknown" if GitHub.single_or_multi_tenant_enterprise?
        return "localhost" unless GitHub::AppEnvironment.production?
        GitHub.server_site || local_host_name
      end

      # An async hydro publisher that publishes messages in a background thread.
      # Messages are buffered and flushed in batches at 2 second intervals.
      def hydro_publisher
        return @hydro_publisher if defined?(@hydro_publisher)

        GitHub.dogstats.increment("hydro_client.create_publisher", tags: ["publisher:async"])

        instrumenter = Hydro::Instrumenter.new
        Hydro::DatadogReporter.start(
          dogstatsd: -> { GitHub.dogstats },
          client_id: GitHub.hydro_metrics_namespace,
          instrumenter: instrumenter,
          default_tags: ["publisher:async"]
        )

        @hydro_publisher = hydro_client.publisher(
          sink: hydro_sink,
          site: hydro_site,
          encoder: hydro_encoder,
          default_headers_proc: DEFAULT_HEADERS_PROC,
          instrumenter: instrumenter
        )
      end

      def hydro_request_analytics_publisher
        return @hydro_request_analytics_publisher if defined?(@hydro_request_analytics_publisher)

        instrumenter = Hydro::Instrumenter.new
        Hydro::DatadogReporter.start(
          dogstatsd: -> { GitHub.dogstats },
          client_id: GitHub.hydro_metrics_namespace,
          instrumenter: instrumenter,
          default_tags: ["publisher:request_analytics"]
        )

        @hydro_request_analytics_publisher = hydro_client.publisher(
          sink: hydro_request_analytics_sink,
          site: hydro_site,
          encoder: hydro_encoder,
          default_headers_proc: DEFAULT_HEADERS_PROC,
          instrumenter: instrumenter
        )
      end

      def hydro_request_analytics_sink(env = GitHub::AppEnvironment.env)
        @manual_hydro_flushing_enabled = true

        if enable_kafka_sink?(env)
          # The Hydro::KafkaSink automatically flushes every 2 seconds. We want
          # to avoid manually flushing because each flush will force a produce
          # operation and diminish throughput. If we service 5 requests in
          # 2 seconds, we'd like to batch all events into a single produce operation
          # rather than 5 individual produce operations.
          # This config is disabled in development mode so that we flush
          # buffered messages between web requests.
          @manual_hydro_flushing_enabled = false unless env == "development"

          max_buffer_size = GitHub.environment.fetch("HYDRO_MAX_BUFFER_SIZE", 1000).to_i
          max_queue_size = GitHub.environment.fetch("HYDRO_MAX_QUEUE_SIZE", 5000).to_i

          original_kafka_async_sink = hydro_kafka_request_analytics_sink(env, {
            producer_options: {
              retry_backoff: 1,
              delivery_interval: 2,
              delivery_threshold: 1000,
              max_buffer_size: max_buffer_size,
              max_queue_size: max_queue_size,
              idempotent: hydro_idempotent_publishing?,
            },
          })

          new_kafka_async_sink = Hydro::AsyncSink.new(
              sink: hydro_kafka_request_analytics_sink(env, {
              async: false,
              producer_options: {
                retry_backoff: 1,
                idempotent: hydro_idempotent_publishing?,
              },
              close_timeout: MAX_SHUTDOWN_TIME - 5,
            }),
            flush_interval: 2.seconds,
            flush_threshold: 1000,
            max_buffer_size: max_buffer_size,
          )

          actor = Hydro::CutoverSink::Actor.new

          kafka_sink = Hydro::CutoverSink.new(
            original: original_kafka_async_sink,
            cutover: new_kafka_async_sink,
            toggle: -> (messages, _options = {}) {
              if messages.any? { |m| m.headers[:async_sink] }
                messages.each { |m| m.headers[:async_sink] = "true" }
                return true
              end

              if GitHub.flipper[:hydro_async_sink].enabled?(actor)
                # Mutate headers on each message to indicate that the message was delivered via the AsyncSink
                # for validation.
                messages.each { |m| m.headers[:async_sink] = "true" }
                true
              end
            }
          )

          if env == "development"
            # for easy debugging of what's getting published:
            Hydro::Sink.tee(hydro_log_sink, kafka_sink)
          else
            Hydro::CutoverSink.new(
              original: kafka_sink,
              cutover: Hydro::AsyncSink.new(
                sink: Hydro::FallbackSink.new(
                  primary: hydro_gateway_sink("request-analytics"),
                  fallback: kafka_sink,
                ),
                flush_interval: 2.seconds,
                flush_threshold: 100,
              ),
              toggle: -> (messages, _options = {}) {
                GitHub.flipper[:hydro_gateway_publish].enabled?(actor) ||
                  messages.any?(&:compress)
              }
            )
          end
        elsif env == "test"
          memory_sink = Hydro::MemorySink.new
          Hydro::Sink.tee(memory_sink, hydro_log_sink)
        else
          Hydro::NoopSink.new
        end
      end

      # The underlying sink to which encoded Hydro messages will be written
      def hydro_sink(env = GitHub::AppEnvironment.env)
        @manual_hydro_flushing_enabled = true

        if enable_kafka_sink?(env)
          # The Hydro::KafkaSink automatically flushes every 2 seconds. We want
          # to avoid manually flushing because each flush will force a produce
          # operation and diminish throughput. If we service 5 requests in
          # 2 seconds, we'd like to batch all events into a single produce operation
          # rather than 5 individual produce operations.
          # This config is disabled in development mode so that we flush
          # buffered messages between web requests.
          @manual_hydro_flushing_enabled = false unless env == "development"

          max_buffer_size = GitHub.environment.fetch("HYDRO_MAX_BUFFER_SIZE", 1000).to_i
          max_queue_size = GitHub.environment.fetch("HYDRO_MAX_QUEUE_SIZE", 5000).to_i

          original_kafka_async_sink = hydro_kafka_sink(
            "async",
            env,
            {
              producer_options: {
                retry_backoff: 1,
                delivery_interval: 2,
                delivery_threshold: 1000,
                max_buffer_size: max_buffer_size,
                max_queue_size: max_queue_size,
                idempotent: hydro_idempotent_publishing?,
              },
            })

          new_kafka_async_sink = Hydro::AsyncSink.new(
            sink: hydro_kafka_sink(
              "async_external",
              env,
              {
                async: false,
                producer_options: {
                  retry_backoff: 1,
                  idempotent: hydro_idempotent_publishing?,
                },
                close_timeout: MAX_SHUTDOWN_TIME - 5,
              }
            ),
            flush_interval: 2.seconds,
            flush_threshold: 1000,
            max_buffer_size: max_buffer_size,
          )

          actor = Hydro::CutoverSink::Actor.new

          kafka_sink = Hydro::CutoverSink.new(
            original: original_kafka_async_sink,
            cutover: new_kafka_async_sink,
            toggle: -> (messages, _options = {}) {
              if messages.any? { |m| m.headers[:async_sink] }
                messages.each { |m| m.headers[:async_sink] = "true" }
                return true
              end

              if GitHub.flipper[:hydro_async_sink].enabled?(actor)
                # Mutate headers on each message to indicate that the message was delivered via the AsyncSink
                # for validation.
                messages.each { |m| m.headers[:async_sink] = "true" }
                true
              end
            }
          )

          if env == "development"
            # for easy debugging of what's getting published:
            Hydro::Sink.tee(kafka_sink, hydro_log_sink)
          else
            Hydro::CutoverSink.new(
              original: kafka_sink,
              cutover: Hydro::AsyncSink.new(
                sink: Hydro::FallbackSink.new(
                  primary: hydro_gateway_sink,
                  fallback: kafka_sink,
                ),
                flush_interval: 2.seconds,
                flush_threshold: 100,
              ),
              toggle: -> (messages, _options = {}) {
                GitHub.flipper[:hydro_gateway_publish].enabled?(actor) ||
                  messages.any?(&:compress)
              }
            )
          end
        elsif env == "test"
          memory_sink = Hydro::MemorySink.new
          Hydro::Sink.tee(memory_sink, hydro_log_sink)
        else
          Hydro::NoopSink.new
        end
      end

      # Just like #hydro_publisher above, but only for use by
      # GitHub::RuntimeCodeCoverage so that it doesn't interfere with the
      # global publisher ~ this is just shameless copy pasta
      def runtime_code_coverage_hydro_publisher
        return @runtime_code_coverage_hydro_publisher if defined?(@runtime_code_coverage_hydro_publisher)

        GitHub.dogstats.increment("hydro_client.create_publisher", tags: ["publisher:runtime_code_coverage"])

        instrumenter = Hydro::Instrumenter.new
        Hydro::DatadogReporter.start(
          dogstatsd: -> { GitHub.dogstats },
          client_id: GitHub.hydro_metrics_namespace,
          instrumenter: instrumenter,
          default_tags: ["publisher:runtime_code_coverage"]
        )

        @runtime_code_coverage_hydro_publisher = hydro_client.publisher(
          sink: runtime_code_coverage_hydro_sink,
          site: hydro_site,
          encoder: hydro_encoder,
          default_headers_proc: DEFAULT_HEADERS_PROC,
          instrumenter: instrumenter
        )
      end

      # Just like #hydro_sink above, but only for use by
      # GitHub::RuntimeCodeCoverage so that it doesn't interfere with the
      # global sink ~ this is just shameless copy pasta
      def runtime_code_coverage_hydro_sink(env = GitHub::AppEnvironment.env)
        # this is different from above hydro_publisher - don't do this, let hydro_publisher do it
        #@manual_hydro_flushing_enabled = true

        if enable_kafka_sink?(env)
          # The Hydro::KafkaSink automatically flushes every 2 seconds. We want
          # to avoid manually flushing because each flush will force a produce
          # operation and diminish throughput. If we service 5 requests in
          # 2 seconds, we'd like to batch all events into a single produce operation
          # rather than 5 individual produce operations.
          # This config is disabled in development mode so that we flush
          # buffered messages between web requests.

          # this is different from above hydro_publisher - don't do this, let hydro_publisher do it
          #@manual_hydro_flushing_enabled = false unless env == "development"

          # this is different from above hydro_publisher
          max_buffer_size = GitHub.environment.fetch("GH_RUNTIME_CODE_COVERAGE_HYDRO_MAX_BUFFER_SIZE", 100_000).to_i
          max_queue_size = GitHub.environment.fetch("GH_RUNTIME_CODE_COVERAGE_HYDRO_MAX_QUEUE_SIZE", 5000).to_i

          original_kafka_async_sink = hydro_kafka_sink(
            "runtime_coverage",
            env,
            {
              producer_options: {
                retry_backoff: 1,
                delivery_interval: 2,
                delivery_threshold: 1000,
                max_buffer_size: max_buffer_size,
                max_queue_size: max_queue_size,
                idempotent: hydro_idempotent_publishing?,
              },
            })

          kafka_sink = Hydro::AsyncSink.new(
            sink: hydro_kafka_sink(
              "runtime_coverage_external",
              env,
              {
                async: false,
                producer_options: {
                  retry_backoff: 1,
                  idempotent: hydro_idempotent_publishing?,
                },
                close_timeout: MAX_SHUTDOWN_TIME - 5,
              }
            ),
            flush_interval: 2.seconds,
            flush_threshold: 1000,
            max_buffer_size: max_buffer_size,
          )

          actor = Hydro::CutoverSink::Actor.new

          if env == "development"
            # for easy debugging of what's getting published:
            Hydro::Sink.tee(kafka_sink, hydro_log_sink)
          else
            Hydro::CutoverSink.new(
              original: kafka_sink,
              cutover: Hydro::AsyncSink.new(
                sink: Hydro::FallbackSink.new(
                  primary: hydro_gateway_sink,
                  fallback: kafka_sink,
                ),
                flush_interval: 2.seconds,
                flush_threshold: 100,
              ),
              toggle: -> (messages, _options = {}) {
                GitHub.flipper[:hydro_gateway_publish].enabled?(actor) ||
                  messages.any?(&:compress)
              }
            )
          end
        elsif env == "test"
          memory_sink = Hydro::MemorySink.new
          Hydro::Sink.tee(memory_sink, hydro_log_sink)
        else
          Hydro::NoopSink.new
        end
      end

      # A wrapper around the normal async hydro publisher that immediately flushes
      # messages on publish. This publisher should be used sparingly because it
      # doesn't batch as effectively as `GitHub.hydro_publisher` and generates
      # more kafka produce requests.
      def low_latency_hydro_publisher
        return @low_latency_hydro_publisher if defined?(@low_latency_hydro_publisher)

        GitHub.dogstats.increment("hydro_client.create_publisher", tags: ["publisher:low_latency"])

        @low_latency_hydro_publisher = LowLatencyHydroPublisher.new(hydro_publisher)
      end

      # Hydro publisher for publishing content/action specific hydro messages. As we roll out
      # new spam detection on the new unified user generated content stream this publisher
      # will switch to the normal hydro publisher and away from the low latency publisher.
      #
      # Once the user_generated_content_hydro_publisher feature is enabled and ready to be
      # removed all references to GitHub.legacy_user_generated_content_publisher should be
      # replaced with GitHub.hydro_publisher.
      def legacy_user_generated_content_publisher
        if GitHub.flipper[:user_generated_content_hydro_publisher].enabled?
          hydro_publisher
        else
          low_latency_hydro_publisher
        end
      end

      # Hydro publisher for publishing the new unified user generated content hydro message.
      # As we roll out spam detection on this new stream this publisher will switch to the low
      # latency publisher and away from the normal hydro publisher.
      #
      # Once the user_generated_content_hydro_publisher feature is enabled for a while and the
      # legacy_user_generated_content_publisher is no longer needed we should consider whether it
      # makes sense to keep the feature to make it easy to quickly turn off synchronous
      # publishing of user generated content.
      def user_generated_content_hydro_publisher
        if GitHub.flipper[:user_generated_content_hydro_publisher].enabled?
          low_latency_hydro_publisher
        else
          hydro_publisher
        end
      end

      class LowLatencyHydroPublisher
        extend Forwardable

        def_delegators :publisher,
          :sink,
          :batch,
          :start_batch,
          :flush_batch,
          :close,
          :encode,
          :default_topic_format_options

        attr_reader :publisher

        def initialize(publisher)
          @publisher = publisher
        end

        def publish(message, args)
          batching = @publisher.sink.batching?
          result = @publisher.publish(message, **args)
          @publisher.flush_batch
          @publisher.start_batch if batching
          result
        end
      end

      class AqueductFallbackHydroPublisher

        # This publisher has a low timeout and is synchronous.
        # Since we have a fallback that will enqueue a job to retry the publish, we can afford to be more aggressive here.
        def low_timeout_sync_hydro_publisher
          return @low_timeout_sync_hydro_publisher if defined?(@low_timeout_sync_hydro_publisher)

          GitHub.dogstats.increment("hydro_client.create_publisher", tags: ["publisher:low_timeout_sync"])

          instrumenter = Hydro::Instrumenter.new
          Hydro::DatadogReporter.start(
            dogstatsd: -> { GitHub.dogstats },
            client_id: GitHub.hydro_metrics_namespace,
            instrumenter: instrumenter,
            default_tags: ["publisher:low_timeout_sync"]
          )

          sink = GitHub.sync_hydro_sink(
            Rails.env,
            client_options: { connect_timeout: 0.5, socket_timeout: 1 },
            producer_options: { max_retries: 0, ack_timeout: 0.5 },
          )

          @low_timeout_sync_hydro_publisher = GitHub.hydro_client.publisher(
            sink: sink,
            site: GitHub.hydro_site,
            encoder: GitHub.hydro_encoder,
            default_headers_proc: DEFAULT_HEADERS_PROC,
            instrumenter: instrumenter
          )
        end

        def hydro_publisher
          low_timeout_sync_hydro_publisher
        end

        sig { params(payload: T.untyped, schema: T.untyped, partition_key: T.untyped, topic: T.untyped, raise_on_payload_too_large: T.untyped, options: T.untyped).returns(T.nilable(T.any(HydroPublishViaAqueductJob, FalseClass))) }
        def publish(payload, schema:, partition_key: nil, topic: nil, raise_on_payload_too_large: false, **options)
          GitHub.dogstats.increment("hydro.aqueduct_fallback_hydro_publisher.publish", tags: ["schema:#{schema}"])
          result = hydro_publisher.publish(payload, schema:, partition_key:, topic:, **options)

          # If the message is too big, make one retry with compression enabled.
          if !result&.success? && result&.error&.is_a?(Hydro::Sink::MessagesTooLarge) && GitHub.compress_oversized_hydro_messages?
            tags = ["schema:#{options[:schema]}"]
            GitHub.dogstats.increment("hydro_client.retry_with_compression", tags: tags)
            result = hydro_publisher.publish(payload, schema:, partition_key:, topic:, **options.merge(compress: true))
          end

          unless result&.success?
            if result&.error&.is_a?(Hydro::Sink::MessagesTooLarge)
              # Don't enqueue the fallback job if the message is too big - it won't help.
              # Instead, just raise/report an error.
              raise result.error if raise_on_payload_too_large
              GitHub.report_hydro_error(result.error, schema:)
            else
              GitHub.dogstats.increment("hydro.aqueduct_fallback_hydro_publisher.fallback", tags: ["schema:#{schema}"])
              HydroPublishViaAqueductJob.perform_later(payload, schema:, partition_key:, topic:, **options)
            end
          end
        end
      end

      sig { returns(AqueductFallbackHydroPublisher) }
      def aqueduct_fallback_hydro_publisher
        return @aqueduct_fallback_hydro_publisher if defined?(@aqueduct_fallback_hydro_publisher)
        @aqueduct_fallback_hydro_publisher = AqueductFallbackHydroPublisher.new
      end

      def sync_hydro_publisher
        return @sync_hydro_publisher if defined?(@sync_hydro_publisher)

        GitHub.dogstats.increment("hydro_client.create_publisher", tags: ["publisher:sync"])

        instrumenter = Hydro::Instrumenter.new
        Hydro::DatadogReporter.start(
          dogstatsd: -> { GitHub.dogstats },
          client_id: GitHub.hydro_metrics_namespace,
          instrumenter: instrumenter,
          default_tags: ["publisher:sync"]
        )

        @sync_hydro_publisher = hydro_client.publisher(
          sink: sync_hydro_sink,
          site: hydro_site,
          encoder: hydro_encoder,
          default_headers_proc: DEFAULT_HEADERS_PROC,
          instrumenter: instrumenter
        )
      end

      def sync_hydro_sink(env = Rails.env, client_options: {}, producer_options: {})
        if enable_kafka_sink?(env)
          idempotent = hydro_idempotent_publishing?
          kafka_sink = hydro_kafka_sink(
            "sync",
            env,
            {
              async: false,
              client_options: {
                connect_timeout: 1,
                socket_timeout: 5,
              }.merge(client_options),
              producer_options: {
                required_acks: idempotent ? :all : 1,
                max_retries: 2,
                retry_backoff: 0.5,
                ack_timeout: 2,
                idempotent: idempotent,
              }.merge(producer_options),
            }
          )

          if env == "development"
            Hydro::Sink.tee(kafka_sink, hydro_log_sink)
          else
            kafka_sink
          end
        else
          GitHub.hydro_sink(env)
        end
      end

      def enable_kafka_sink?(env = Rails.env)
        (env == "production" && hydro_enabled?) || env == "development"
      end

      def hydro_encoder
        # Report schemas that populate `nil` for scalar fields.
        nil_scalar_handler = ->(error) do
          schema = error.schema.name.gsub(/:+/, ".").downcase.sub("hydro.schemas.", "")
          tags = [
            "schema:#{schema}",
            "field:#{error.field.name}",
          ]
          GitHub.dogstats.increment("hydro_client.nil_scalar", tags: tags)
        end

        Hydro::ProtobufEncoder.new(
          Hydro::Site.new(hydro_site),
          nil_scalar_handler: nil_scalar_handler,
        )
      end

      def hydro_metrics_namespace
        "github-#{GitHub::AppEnvironment.env}"
      end

      def hydro_idempotent_publishing?
        %w[true 1].include? GitHub.environment["HYDRO_IDEMPOTENT_PUBLISHING"]
      end

      def hydro_producer_ssl_enabled?
        Rails.env.production? && !GitHub.single_or_multi_tenant_enterprise?
      end

      # Create a new Hydro::KafkaSink for the given environment.
      #
      # sink_name - required sink name, for metric tagging `sink:<sink_name>`
      # env       - optional environment, defaults to Rails.env
      # options   - optional hash of options to pass to the Hydro::KafkaSink
      def hydro_kafka_sink(sink_name, env = Rails.env, options = {})
        use_ssl = hydro_producer_ssl_enabled?
        if env == "production"
          seed_brokers = self.hydro_seed_brokers(ssl: use_ssl)
          if seed_brokers.none?
            Failbot.report(ArgumentError.new("GitHub.environment['HYDRO_KAFKA_BROKERS'] not set!"))
            return Hydro::NoopSink.new
          end

          if use_ssl
            options.deep_merge!({ client_options: hydro_kafka_ssl_options })
          end
        else
          seed_brokers = GitHub.environment.fetch("HYDRO_KAFKA_BROKERS", DEVELOPMENT_BROKER).split(",")
        end

        # Instead of using the default Hydro.instrumenter (which defaults to the
        # global ActiveSupport::Notifications), we're going to use a separate
        # instrumenter and attach datadog metrics to it directly in order to get
        # client-instance-specific tags.
        instrumenter = Hydro::Instrumenter.new
        Hydro::DatadogReporter.start(
          dogstatsd: -> { GitHub.dogstats },
          client_id: GitHub.hydro_metrics_namespace,
          instrumenter: instrumenter,
          default_tags: ["sink:#{sink_name}"],
        )

        kafka = Hydro::KafkaSink.new(
          **{
            seed_brokers: seed_brokers,
            client_id: "#{hydro_metrics_namespace}-#{local_host_name}",
            instrumenter: instrumenter,
          }.merge(options),
        )

        Hydro::CircuitBreakingSink.new(kafka, tags: ["sink:#{sink_name}"])
      end

      def hydro_kafka_request_analytics_sink(env = Rails.env, options = {})
        use_ssl = hydro_producer_ssl_enabled?
        if env == "production"
          seed_brokers = GitHub.with_hydro_cluster("request-analytics") { self.hydro_seed_brokers(ssl: use_ssl) }
          if seed_brokers.none?
            Failbot.report(ArgumentError.new("GitHub.environment['HYDRO_KAFKA_BROKERS'] not set!"))
            return Hydro::NoopSink.new
          end

          if use_ssl
            options.deep_merge!({ client_options: hydro_kafka_ssl_options })
          end
        else
          seed_brokers = GitHub.environment.fetch("HYDRO_KAFKA_BROKERS", DEVELOPMENT_BROKER).split(",")
        end

        kafka = Hydro::KafkaSink.new(
          **{
            seed_brokers: seed_brokers,
            client_id: "#{hydro_metrics_namespace}-#{local_host_name}",
          }.merge(options),
        )

        Hydro::CircuitBreakingSink.new(kafka, tags: ["sink:request-analytics"])
      end

      attr_accessor :hydro_gateway_url

      def hydro_gateway_sink(cluster = "potomac")
        Hydro::GatewaySink.new(
          client_id: "#{local_host_name}-#{Process.pid}",
          cluster: cluster,
          url: hydro_gateway_url,
          max_retries: 2,
          retry_backoff: 2,
        ) do |faraday|
          faraday.adapter :persistent_excon,
            tcp_nodelay: true,
            keepalive: {
              time: 60,
              intvl: 5,
              probes: 3,
            }
        end
      end

      def hydro_log_sink
        logger = ::Logger.new(GitHub::AppEnvironment.root.join("log/hydro-#{GitHub::AppEnvironment.env}.log"))
        formatter = ->(message) {
          if message.data
            decoded = Hydro::Decoding::ProtobufDecoder.decode(message.data)
          end

          [
            "\e[36m[#{message.timestamp || Time.now}]\e[0m",
            "\e[34m[#{message.topic}]\e[0m",
            "\e[35m#{message.schema}\e[0m",
            "\e[33m#{message.headers} bytes\e[0m",
            "\e[33m#{message.data&.bytesize} bytes\e[0m",
            "\e[37m#{decoded&.to_h.to_json}\e[0m",
          ].join(" ")
        }

        Hydro::LogSink.new(logger, formatter: formatter)
      end

      def hydro_consumer(options = {}, publisher = nil, env = GitHub::AppEnvironment.env)
        deliver_tombstone_messages = options.delete(:deliver_tombstone_messages)
        source = case env
        when "test"
          publisher ||= hydro_publisher
          Hydro::MemorySource.new(**{ sink: publisher.sink }.merge(options))
        when "development", "production"
          hydro_kafka_source(options, env)
        end

        decode_failure_handler = ->(message, error) do
          Failbot.report(error, {
            hydro_msg_topic: message.topic,
            hydro_msg_partition: message.partition,
            hydro_msg_offset: message.offset,
          })
          tags = ["topic:#{message.topic}"]
          GitHub.dogstats.increment("hydro_client.consumer.decode_error", tags: tags)
        end

        hydro_client.consumer(
          source: source,
          decode_failure_handler: decode_failure_handler,
          deliver_tombstone_messages: deliver_tombstone_messages,
        )
      end

      def hydro_consumer_ssl_enabled?
        GitHub::AppEnvironment.production? && !GitHub.single_or_multi_tenant_enterprise?
      end

      def self.hydro_cluster_override
        Thread.current[:hydro_cluster_override]
      end

      # Public: Override the hydro cluster used to build a hydro consumer.
      #
      # Usage:
      #
      #    consumer = GitHub.with_hydro_cluster(:yukon) { GitHub.hydro_consumer }
      #
      def with_hydro_cluster(cluster_name)
        # Only support switching hydro clusters in production.
        # Development and GHES use a single cluster.
        unless GitHub::AppEnvironment.production? && !GitHub.single_or_multi_tenant_enterprise?
          return yield
        end

        original_cluster = HydroConfig.hydro_cluster_override
        Thread.current[:hydro_cluster_override] = cluster_name

        yield
      ensure
        Thread.current[:hydro_cluster_override] = original_cluster
      end

      def hydro_kafka_source(options, env)
        use_ssl = hydro_consumer_ssl_enabled?
        if env == "production"
          seed_brokers = self.hydro_seed_brokers(ssl: use_ssl)
          if seed_brokers.none?
            raise ArgumentError.new("GitHub.environment['HYDRO_KAFKA_BROKERS'] not set!")
          end

          if use_ssl
            options.deep_merge!(hydro_kafka_ssl_options)
          end
        else
          seed_brokers = [DEVELOPMENT_BROKER]
        end

        Hydro::KafkaSource.new(**{
          seed_brokers: seed_brokers,
          client_id: "#{hydro_metrics_namespace}-#{options[:group_id]}-#{local_host_name}",
          socket_timeout: 35, # 5 more than the default session timeout
        }.merge(options))
      end

      def flush_hydro_batches?
        !!@manual_hydro_flushing_enabled
      end

      def compress_oversized_hydro_messages?
        GitHub.flipper[:compress_oversized_hydro_messages].enabled?
      end

      def hydro_buffered_message_topic_counts
        ObjectSpace.each_object(Hydro::KafkaSink).map do |sink|
          begin
            # Truly hideous, but there is no public API for this info :/
            # Collects pending message counts from the sync kafka client.
            async = false
            queue = nil
            sync_producer = sink.send(:producer)

            if sink.send(:async?)
              async = true
              sync_producer = sink.send(:producer)
                .instance_variable_get("@worker")
                .instance_variable_get("@producer")
              queue = sink.send(:producer).instance_variable_get("@queue")
            end

            pending = sync_producer.instance_variable_get("@pending_message_queue")
              .instance_variable_get("@messages")
              .group_by(&:topic)
              .transform_values(&:size)

            operations = []
            if queue
              queued = queue.size.times.reduce(Hash.new { |h, k| h[k] = 0 }) do |acc, _|
                begin
                  operation, args = queue.pop(true)

                  if operation == :produce
                    acc[args.last[:topic]] += 1
                  end

                  operations << operation

                  acc
                rescue ThreadError
                  break acc
                end
              end
            end

            worker_status = sink.send(:producer).instance_variable_get("@worker_thread")&.status

            {
              async: async,
              queued: queued,
              pending: pending,
              buffer_size: sync_producer.buffer_size,
              buffer_bytesize: sync_producer.buffer_bytesize,
              worker_status: worker_status,
              operation_count: operations.group_by(&:to_sym).map { |k, v| [k, v.count] }.to_h,
              operations: operations.take(100),
            }
          rescue NoMethodError => e
            { "error" => e.message }
          end
        end
      end

      def hydro_debug?
        GitHub.local_host_name.include?("worker")
      end

      # Flushes buffered hydro messages before exiting. Blocks for up to
      # `MAX_SHUTDOWN_TIME` seconds before timing out. Under the hood, hydro-client
      # flushes messages buffered in the kafka client to kafka.
      def close_hydro(timeout:)
        return unless hydro_sink_initialized?

        if GitHub.hydro_debug?
          # Dump debugging info
          Hydro.instrumenter.subscribe(Hydro::GatewaySink::REQUEST_EVENT) do |*args|
            hydro_logger.info(args)
          end
          Hydro.instrumenter.subscribe(Hydro::AsyncSink::FLUSH_EVENT) do |*args|
            hydro_logger.info(args)
          end
          Hydro.instrumenter.subscribe(Hydro::AsyncSink::FLUSH_ERROR_EVENT) do |*args|
            hydro_logger.info(args)
          end
          Hydro.instrumenter.subscribe(Hydro::AsyncSink::BUFFER_EVENT) do |*args|
            hydro_logger.info(args)
          end
          hydro_logger.info("called GitHub.close_hydro")
          ObjectSpace.each_object(Hydro::AsyncSink::Buffer).each do |buffer|
            hydro_logger.info(buffer.inspect)
          end
        end

        GitHub.dogstats.distribution_time("hydro_client.kafka.shutdown") do
          begin
            Timeout.timeout(timeout) do
              GitHub.hydro_publisher.sink.close
            end
          rescue Timeout::Error
            dropped = {
              hydro_publisher: hydro_buffered_message_topic_counts,
            }

            report_hydro_error(Hydro::DirtyExit.new, {
              hydro_dropped: dropped,
            })
          end
        end
      end

      def hydro_seed_brokers(ssl: true)
        brokers = HydroConfig.lookup_hydro_seed_brokers

        # Fall back to potomac boot brokers if we can't load brokers from DNS.
        # Don't fall back if a specific hydro cluster was requested.
        if !HydroConfig.hydro_cluster_override && !brokers.many?
          brokers = GitHub.environment["HYDRO_KAFKA_BROKERS"].to_s.split(",").shuffle
        end

        # On GHES, ports should be explicitly configured and SSL is never used,
        # so return the addresses unchanged (unless no port is specified).
        if GitHub.enterprise?
          if brokers.any? { |broker| broker[/:\d+\Z/].nil? }
            Failbot.report(ArgumentError.new("GitHub.environment['HYDRO_KAFKA_BROKERS'] contains address without port!"))
          end
          brokers.map! { |broker| broker[/:\d+\Z/] ? broker : "#{broker}:9092" }
          return brokers.shuffle
        end

        # If any brokers include an explicitly configured non-standard port, don't override with
        # 9092 or 9093.
        if GitHub.multi_tenant_enterprise? && brokers.any? { |broker| broker[/:\d+\Z/] && !broker[/909[2,3]/] }
          return brokers.shuffle
        end

        port = (ssl && GitHub::AppEnvironment.production?) ? 9093 : 9092
        brokers.map { |broker| broker.split(":").first + ":#{port}" }
      end

      def self.lookup_hydro_seed_brokers
        return [] unless GitHub::AppEnvironment.production? && !GitHub.single_or_multi_tenant_enterprise?
        sites = %w[ash1-iad va3-iad ac4-iad].shuffle

        # preferentially use the site-local consul DNS for lookup
        if sites.delete(GitHub.server_site)
          sites.unshift(GitHub.server_site)
        end

        if HydroConfig.hydro_cluster_override
          return sites.map { |site| "hydro-kafka-#{HydroConfig.hydro_cluster_override}.service.#{site}.consul" }
        end

        sites.map { |site| "hydro-kafka-potomac.service.#{site}.consul" }
      end

      def self.lookup_hydro_srv_record(domain)
        Resolv::DNS.open do |dns|
          # _Very_ rarely this fails with a `NoMethodError` deep in resolv - let's retry a few times
          # if we encounter that problem.
          retry_count = 0
          begin
            dns.getresources(domain, Resolv::DNS::Resource::IN::SRV)
          rescue NoMethodError
            retry_count += 1
            retry_count > 3 ? raise : retry
          end
        end
      end

      def hydro_kafka_ssl_options
        return {} unless GitHub::AppEnvironment.production?

        { ssl_ca_cert_file_path: self.hydro_ssl_cert_filename }
      end

      def hydro_ssl_cert_filename
        GitHub.environment.fetch("GH_HYDRO_SSL_CA_CERTS", "/etc/ssl/certs/ca-certificates.crt")
      end

      def report_hydro_error(error, context = {})
        # If an error is a known non-hydro error, report to the main github bucket.
        if error.is_a?(ActiveRecord::ActiveRecordError) || error.is_a?(GitRPC::Error)
          Failbot.report(error)
          return
        end

        if error.is_a?(Hydro::Sink::BufferOverflow)
          # If kafka is down for an extended period, internal producer buffers will fill up. When
          # buffers are full, any attempt to produce will generate a buffer overflow error. To avoid
          # spamming failbot in production and exception logs in GHES, we report this metric
          GitHub.dogstats.increment("hydro_client.sink.message_dropped", tags: ["error:#{error.class}"])
          GitHub.stats.increment("hydro_client.sink.message_dropped.#{error.class}") if GitHub.enterprise?
        elsif error.is_a?(Hydro::GatewaySink::DeliveryFailure)
          failure_counts = error.failures.map do |failure|
            [failure[:message].schema, failure[:error_key]]
          end.tally

          Failbot.report(error, { app: "github-hydro", hydro_dropped: failure_counts }.merge(context))

          error.failures.each do |failure|
            tags = ["schema:#{failure[:message].schema}", "error:#{failure[:error_key]}"]
            GitHub.dogstats.increment("hydro_client.gateway_sink.delivery_failure", tags: tags)
          end
        elsif error.is_a?(Hydro::Protobuf::InvalidValueError) || error.is_a?(Hydro::Protobuf::InvalidEnumValueError)
          Failbot.report(error, { app: "github-hydro-serialization" }.merge(context))
        else
          Failbot.report(error, { app: "github-hydro" }.merge(context))
        end
      end

      # Public: Returns a hydro type_url. Automatically handles schema with or
      # without "hydro.schemas." prefix.
      #
      # Examples:
      #   > GitHub::Config::HydroConfig.build_type_url("foo.v1.Bar")
      #  => "hydro-schemas.github.net/hydro.schemas.foo.v1.Bar"
      #   > GitHub::Config::HydroConfig.build_type_url("hydro.schemas.foo.v1.Bar")
      #  => "hydro-schemas.github.net/hydro.schemas.foo.v1.Bar"
      #
      # Returns a String.
      def self.build_type_url(schema)
        schema = "hydro.schemas.#{schema}" unless schema.start_with?("hydro.schemas.")
        ::Hydro::TYPE_URL_PREFIX.join(schema).to_s
      end

      attr_accessor :hydro_aggregation_api_url

      def hydro_aggregation_api_enabled?
        GitHub.flipper[:hydro_aggregation_api_enabled].enabled?
      end

      def hydro_aggregation_api_client
        HydroAggregationApi::Client.build(url: hydro_aggregation_api_url) do |faraday|
          faraday.adapter :persistent_excon,
            tcp_nodelay: true,
            keepalive: {
              time: 60,
              intvl: 5,
              probes: 3,
            }
        end
      end
    end
  end

  extend Config::HydroConfig

  at_exit do
    GitHub.close_hydro(timeout: GitHub::Config::HydroConfig::MAX_SHUTDOWN_TIME)
  end
end
