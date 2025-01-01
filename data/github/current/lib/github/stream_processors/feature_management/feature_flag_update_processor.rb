# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module FeatureManagement
      class FeatureFlagUpdateProcessor < BaseProcessor
        extend T::Helpers

        # Order is important here, callbacks are executed
        # in the reverse order they're defined here
        set_callback :message, :around, :pause_on_transient_errors
        set_callback :message, :around, :retry_on_transient_errors

        TRANSIENT_ERRORS_MAX_RETRIES = 3
        TRANSIENT_ERRORS_TO_RETRY_ON = T.let([
          # frequently occuring
          Memcached::ATimeoutOccurred,
          Memcached::ReadFailure,
          Memcached::ClientError,
          Memcached::HostnameLookupFailure,
          Memcached::ConnectionFailure,
          Memcached::SystemError,

          # less frequently occuring, errors of the weirder sort
          Memcached::ConnectionBindFailure,
          Memcached::ConnectionDataDoesNotExist,
          Memcached::ConnectionDataExists,
          Memcached::ConnectionSocketCreateFailure,
          Memcached::CouldNotOpenUnixSocket,
          Memcached::Failure,
          Memcached::FetchWasNotCompleted,
          Memcached::PartialRead,
          Memcached::ProtocolError,
          Memcached::ServerDelete,
          Memcached::ServerEnd,
          Memcached::ServerError,
          Memcached::SomeErrorsWereReported,
          Memcached::TheHostTransportProtocolDoesNotMatchThatOfTheClient,
          Memcached::UnknownReadFailure,
          Memcached::WriteFailure,
        ], T::Array[T.class_of(StandardError)])

        TRANSIENT_ERROR_PAUSE_DURATION = T.let(2.minutes, ActiveSupport::Duration)
        TRANSIENT_ERRORS_TO_PAUSE_ON = T.let(TRANSIENT_ERRORS_TO_RETRY_ON.concat([
          Memcached::ServerIsMarkedDead,
        ]), T::Array[T.class_of(StandardError)])

        FEATURE_FLAG_UPDATE_PROCESSOR_INDEX = T.let(GitHub.environment.fetch("FEATURE_FLAG_UPDATE_PROCESSOR_INDEX", 0).to_i, Integer)

        DEFAULT_GROUP_ID_TEMPLATE = T.let("github-%{env}-%{memcached_host}-feature_flag_update_processor", String)
        DEFAULT_SUBSCRIBE_TO = T.let([
          /featureflags\.data\.v0\.FeatureFlag\Z/,
          /featureflags\.data\.v0\.Segment\Z/,
        ], T::Array[Regexp])

        ALL_GROUP_ID = T.let("github-#{Rails.env}-all-feature_flag_update_processor", String)

        # The slack channel pause notification will be posted to
        self.slack_pause_notifications_channel = "#feature-management-alerts"

        # This is the timeout used for determining if a given Kafka consumer has
        # failed or quit due to e.g. a deploy. Setting it to a lower value is NOT
        # recommended if your Hydro processor interacts with the database, since
        # Freno may wait up to 30 seconds when throttling writes. Processors that
        # do not interact with a database may lower this value to allow faster
        # consumer group rebalancing during deploys and processor failures.
        #
        # See https://kafka.apache.org/documentation/#session.timeout.ms
        options[:session_timeout] = 60.seconds

        # This value must be greater than "session_timeout"
        #
        # See https://github.com/zendesk/ruby-kafka#understanding-timeouts
        options[:socket_timeout] = 65.seconds

        # When the processor starts consuming from a partition for the first time and has no committed offsets,
        # `start_from_beginning` determines if should start from the beginning of the log (i.e. the oldest available messages)
        # or the end of the log (i.e. the newest available messages).
        #
        # This is the equivalent of the java client `auto.offset.reset` consumer config.
        # See: https://kafka.apache.org/documentation/#consumerconfigs_auto.offset.reset
        options[:start_from_beginning] = true

        # Other options you may want to set...
        #
        # This will cause the Kafka consumer to wait until there is at least a
        # given number of bytes available to fetch; but the consumer will wait
        # no longer than "max_wait_time" (described below). This allows the
        # processor to wait for a large enough batch of data. The default is
        # 1 byte, meaning data will be fetched as soon as it's available. Value
        # below is for example purposes only and not a recommendation; the default
        # value of 1 should be suitable for most cases.
        # See https://kafka.apache.org/documentation/#fetch.min.bytes
        # options[:min_bytes] = 1.kilobyte
        #
        # This is the maximum amount of time the Kafka consumer will wait to
        # fetch data. The default is 500ms (0.5.seconds). Value below is for
        # example purposes only and not a recommendation; the default value of
        # 500ms should be suitable for most cases.
        # options[:max_wait_time] = 1.second
        #
        # This is the maximum amount of data that will be fetched at a time. This
        # value is specified in bytes, so the number of distinct Hydro messages
        # fetched depends on the size of those messages. The default is 1MB. You
        # may want to consider lowering this if processing each batch of messages
        # is taking more than 60 seconds in order to ensure that your processor
        # shuts down in a timely manner during deploys.
        # See https://kafka.apache.org/documentation/#max.partition.fetch.bytes
        # options[:max_bytes_per_partition] = 100.kilobytes

        # Override class methods from lib/github/stream_processors/processor_pausing.rb

        sig { params(pause_key: String).returns(T::Boolean) }
        def self.paused?(pause_key)
          ActiveRecord::Base.connected_to(role: :reading) do
            # returns true if either the all group id or the provided pause key is set in kv.
            GitHub.kv.exists("processor-paused-#{ALL_GROUP_ID}").value! || GitHub.kv.exists("processor-paused-#{pause_key}").value!  # rubocop:todo GitHub/DoNotUseGlobalKv
          end
        end

        sig { params(pause_key: String).returns(T.nilable(Time)) }
        def self.paused_at(pause_key)
          # returns the earliest paused at time for either the all group id or the provided pause key
          raw_value = GitHub.kv.get("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          raw_value_all = GitHub.kv.get("processor-paused-#{ALL_GROUP_ID}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          return unless raw_value || raw_value_all

          paused_at = nil
          if raw_value
            data = JSON.parse(raw_value, symbolize_names: true)
            paused_at = Time.parse(data[:at])
          end
          if raw_value_all
            data = JSON.parse(raw_value_all, symbolize_names: true)
            paused_at_all = Time.parse(data[:at])
            paused_at = paused_at.nil? ? paused_at_all : [paused_at, paused_at_all].min
          end
          paused_at
        end

        sig { params(pause_key: String).returns(T.nilable(String)) }
        def self.pause_reason(pause_key)
          # returns the reason the pause from either the all group id or the provided pause key
          raw_value_all = GitHub.kv.get("processor-paused-#{ALL_GROUP_ID}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          if raw_value_all
            return JSON.parse(raw_value_all, symbolize_names: true).dig(:reason)
          end

          raw_value = GitHub.kv.get("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          return unless raw_value

          JSON.parse(raw_value, symbolize_names: true).dig(:reason)
        end

        sig { params(pause_key: String).returns(T.nilable(Time)) }
        def self.resumes_at(pause_key)
          # returns the latest resumes at time for either the all group id or the provided pause key
          raw_value = GitHub.kv.get("processor-paused-#{pause_key}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          raw_value_all = GitHub.kv.get("processor-paused-#{ALL_GROUP_ID}").value! # rubocop:todo GitHub/DoNotUseGlobalKv
          return unless raw_value || raw_value_all

          data = JSON.parse(raw_value, symbolize_names: true)
          data_all = JSON.parse(raw_value_all, symbolize_names: true)

          return nil unless data[:expires].present? && data_all[:expires].present?

          resumes_at = Time.parse(data[:expires])
          resumes_at_all = Time.parse(data_all[:expires])

          [resumes_at, resumes_at_all].max
        end

        sig { params(group_id: T.nilable(String), subscribe_to: T.nilable(String), rescue_from_standard_error: T::Boolean, use_memcached_host_group_id: T::Boolean, kwargs: T.untyped).void }
        def initialize(group_id: nil, subscribe_to: nil, rescue_from_standard_error: Rails.env.production?, use_memcached_host_group_id: false, **kwargs)
          # Define these here so Sorbet doesn't complain
          @memcached_client = T.let(nil, T.nilable(::FeatureFlag::Cache::IMemcachedClient))
          @use_memcached_host_group_id = use_memcached_host_group_id

          super
        end

        # Public: Configure the Hydro processor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          allow_fallback = GitHub::AppEnvironment.test? || Rails.env.development? # only allow fallback when running in dev/tests to avoid issue with the fact the servers do not match the site in the test environment
          memcached_servers = ::FeatureFlag::Cache::MemcachedClient.servers(allow_fallback)

          if memcached_servers.empty?
            raise "No memcached servers configured for FeatureFlag::Cache"
          end

          if FEATURE_FLAG_UPDATE_PROCESSOR_INDEX > memcached_servers.length - 1
            options[:group_id] ||= ALL_GROUP_ID # Prevent the pods from cycling if the memcached server can't be found

            stats.increment(
              "github.stream_processors.feature_flag_update_processor.no_memcached_server",
              tags: default_stats_tags + ["memcached_servers_count:#{memcached_servers.length}", "index:#{FEATURE_FLAG_UPDATE_PROCESSOR_INDEX}"]
            )

            GitHub.logger.error("Failed to look up memcached server", {
              "code.namespace" => self.class.name,
              "code.function" => "setup",
              "gh.processor.name" => self.class.name,
              "gh.catalog_service" => logical_service,
              "gh.processor.servers" => memcached_servers,
              "gh.processor.server_index" => FEATURE_FLAG_UPDATE_PROCESSOR_INDEX,
              "gh.stamp" => GitHub::Config::Proxima.current_stamp_or_dotcom,
            })
            return
          end

          server = T.must(memcached_servers[FEATURE_FLAG_UPDATE_PROCESSOR_INDEX])
          @memcached_client = create_memcached_client(server)

          if @use_memcached_host_group_id
            # Use the memcached server as part of the group id to ensure that each memcached server has its own consumer group
            # Replace characters not allowed in consumer group names
            cleaned_memcached_host = server.gsub(/[^a-zA-Z0-9\._\-]+/, "-")
            default_group_id = DEFAULT_GROUP_ID_TEMPLATE % { env: Rails.env, memcached_host: cleaned_memcached_host }
            options[:group_id] ||= default_group_id
          else
            # When @use_memcached_host_group_id is false, use the ALL_GROUP_ID. This should only be false in general stream processor tests
            # or when running in the devtools/stream_processor UI, where we want to set the group id to the "all" group so that pause/resume
            # actions affect all instances of the processor.
            options[:group_id] ||= ALL_GROUP_ID
          end

          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          GitHub.logger.info("Set up FeatureFlagUpdateProcessor", {
            "code.namespace" => self.class.name,
            "code.function" => "setup",
            "gh.processor.name" => self.class.name,
            "gh.processor.consumer_group_name" => options[:group_id],
            "gh.processor.subscribe_to" => options[:subscribe_to],
            "gh.catalog_service" => logical_service,
          })
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          GitHub.logger.info("Processing message", {
            "code.namespace" => self.class.name,
            "code.function" => "process_message",

            "messaging.kafka.source.name" => message.topic,
            "messaging.kafka.source.partition" => message.partition,
            "messaging.kafka.message.offset" => message.offset,
            "messaging.kafka.message.body" => message.value,
            "messaging.kafka.message.key" => message.key,

            "gh.feature_flag_update_processor.operation" => message.value.present? ? "set" : "delete",
          })
          return message.skip("feature flag disabled") if GitHub.flipper[:feature_flag_update_processor_disabled].enabled?
          return message.skip("no memcached server for index") unless @memcached_client

          if message.topic == "featureflags.data.v0.FeatureFlag"
            process_feature_flag_message(message, @memcached_client)
          elsif message.topic == "featureflags.data.v0.Segment"
            process_segment_message(message, @memcached_client)
          end
        end

        private

        # This stream processor is not using MySQL at all but fully depends on Memcached.
        # We're overriding the mysql database selection here to avoid database selection errors
        # which depend on timestamps we don't have when receiving tombstone messages
        #
        # Reference: https://github.com/github/github/blob/ab09832c1c59ff969fca29242db8b3c5e5d3a0de/lib/database_selector/last_operations.rb#L230-L236
        sig { params(blk: T.nilable(Proc)).void }
        def mysql_database_selection(&blk)
          if blk
            blk.call
          end
        end

        sig { params(_blk: T.proc.void).void }
        def pause_on_transient_errors(&_blk)
          yield
        rescue StandardError => error # rubocop:disable Lint/GenericRescue
          if pause_on_transient_error?(error)
            report_error(error)

            stats.increment("github.stream_processors.transient_error.pause", tags: default_stats_tags + ["error:#{error.class}"])
            pause(expires: TRANSIENT_ERROR_PAUSE_DURATION.from_now, reason: "Transient error: #{error.class}")
          else
            raise
          end
        end

        sig { params(_blk: T.proc.void).void }
        def retry_on_transient_errors(&_blk)
          attempts = 0

          begin
            yield
          rescue StandardError => error # rubocop:disable Lint/GenericRescue
            if attempts < TRANSIENT_ERRORS_MAX_RETRIES && retry_on_transient_error?(error)
              attempts += 1
              stats.increment("github.stream_processors.transient_error.retry", tags: default_stats_tags + ["error:#{error.class}"])
              log_retry(error, attempts)
              sleep(attempts)

              retry
            else
              raise
            end
          end
        end

        sig { params(error: T.any(StandardError, Exception)).returns(T::Boolean) }
        def pause_on_transient_error?(error)
          TRANSIENT_ERRORS_TO_PAUSE_ON.any? { |error_class| error.is_a?(error_class) }
        end

        sig { params(error: T.any(StandardError, Exception)).returns(T::Boolean) }
        def retry_on_transient_error?(error)
          TRANSIENT_ERRORS_TO_RETRY_ON.any? { |error_class| error.is_a?(error_class) }
        end

        sig { params(message: GitHub::StreamProcessors::Message, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def process_feature_flag_message(message, cache_client)
          if message.value.present?
            add_feature_flag_entry(message, cache_client)
          else
            remove_feature_flag_entry(message, cache_client)
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def process_segment_message(message, cache_client)
          if message.value.present?
            add_segment_entry(message, cache_client)
          else
            remove_segment_entry(message, cache_client)
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def add_feature_flag_entry(message, cache_client)
          feature_flag_name = message.value[:name]
          feature_flag_hash = message.value.stringify_keys

          # Convert state to boolean gate
          state = feature_flag_hash["state"]
          feature_flag_hash["boolean_gate"] = state == :SHIPPED if state.is_a?(Symbol)
          feature_flag_hash["boolean_gate"] = state == "SHIPPED" if state.is_a?(String)
          feature_flag_hash["boolean_gate"] = state == 3 if state.is_a?(Integer)

          feature_flag = Vexi::FeatureFlag.from_hash(feature_flag_hash)

          check_and_set_feature_flag_cache_entry(feature_flag_name, feature_flag, cache_client)
        end

        sig { params(message: GitHub::StreamProcessors::Message, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def add_segment_entry(message, cache_client)
          segment_name = message.value[:name]
          segment = Vexi::Segment.from_hash(message.value.stringify_keys)
          segment.actors = Vexi::Adapters::ArrayActorCollection.new(segment.actors.keys.sort)

          # For default segments, update the feature flag cache entry instead of the segment cache entry
          if is_default_segment_name(segment_name)
            feature_flag_name = segment_name.delete_prefix("_")
            check_and_set_feature_flag_cache_entry(feature_flag_name, segment, cache_client)
          else
            cache_key = "#{::FeatureFlag::Config::CACHE_SEGMENT_KEY_PREFIX}#{segment_name}"
            set_cache_entry(cache_key, segment, cache_client)
          end

        end

        sig { params(message: GitHub::StreamProcessors::Message, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def remove_feature_flag_entry(message, cache_client)
          cache_key = "#{::FeatureFlag::Config::CACHE_FEATURE_FLAG_KEY_PREFIX}#{message.key}"

          # Update the feature flag cache entry with a disabled flag with the default not found TTL instead of removing the cache entry to avoid race conditions.
          set_cache_entry(cache_key, Vexi::FeatureFlag.new(message.key, boolean_gate: false), cache_client, ::FeatureFlag::Config::PRODUCTION_CACHE_NOT_FOUND_TTL)
        end

        sig { params(message: GitHub::StreamProcessors::Message, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def remove_segment_entry(message, cache_client)
          segment_name = message.key
          # For default segments, update the feature flag cache entry with an empty segment instead of removing the segment cache entry
          if is_default_segment_name(segment_name)
            feature_flag_name = segment_name.delete_prefix("_")
            check_and_set_feature_flag_cache_entry(feature_flag_name, ::Vexi::Segment.new(segment_name), cache_client)
          else
            cache_key = "#{::FeatureFlag::Config::CACHE_SEGMENT_KEY_PREFIX}#{segment_name}"
            remove_cache_entry(cache_key, cache_client)
          end
        end

        sig { params(feature_flag_name: String, payload: T.any(Vexi::FeatureFlag, Vexi::Segment), cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def check_and_set_feature_flag_cache_entry(feature_flag_name, payload, cache_client)
          cache_key = "#{::FeatureFlag::Config::CACHE_FEATURE_FLAG_KEY_PREFIX}#{feature_flag_name}"
          retry_count = 0
          operation = "unknown"
          response = time("feature_flag_update_processor.memcached_check_and_set") do
            loop do
              existing_feature_flag = cache_client.get(cache_key)
              if existing_feature_flag.nil?
                # If the feature flag does not exist in the cache, we can add it.
                feature_flag = if payload.is_a?(Vexi::FeatureFlag)
                  # Just use the payload if it is a feature flag
                  payload
                else
                  # Do not create a feature flag for an empty segment in the cache
                  if payload.actors.length == 0
                    operation = "noop"
                    break
                  end
                  # Or create a default feature flag and add the actors from the segment
                  ff = Vexi::FeatureFlag.create_default(feature_flag_name)
                  ff.actors = payload.actors
                  ff
                end
                # Use add to avoid overwriting any data written since we did the get above
                operation = "add"
                result = cache_client.add(cache_key, feature_flag, 0, false)
                break if !!result
              else
                operation = "cas"
                result = cache_client.cas(cache_key, 0, false) do |value|
                  if payload.is_a?(Vexi::FeatureFlag)
                    # Use the payload as the feature flag, but copy the existing actors from value
                    new_value = payload
                    new_value.actors = value.actors if value.respond_to?(:actors)
                    new_value
                  else
                    # Use the existing feature flag, but update the actors from the payload
                    new_value = value
                    new_value.actors = payload.actors if payload.respond_to?(:actors)
                    new_value
                  end
                end
                break if !!result
              end
              retry_count += 1
              raise "Failed to update feature flag cache entry after #{retry_count} attempts" if retry_count >= 5
            end
            true
          end
        ensure
          stats.increment(
            "github.stream_processors.feature_flag_update_processor.memcached_operations",
            tags: default_stats_tags + ["operation:#{operation}", "success:#{response == true}", "retry_count:#{retry_count}"]
          )
        end

        sig { params(cache_key: String, payload: T.any(Vexi::FeatureFlag, Vexi::Segment), cache_client: ::FeatureFlag::Cache::IMemcachedClient, ttl: Integer).void }
        def set_cache_entry(cache_key, payload, cache_client, ttl = 0)
          response = time("feature_flag_update_processor.memcached_set") do
            cache_client.set(cache_key, payload, ttl, false)
          end
        ensure
          stats.increment(
            "github.stream_processors.feature_flag_update_processor.memcached_operations",
            tags: default_stats_tags + ["operation:set", "success:#{response == true}"]
          )
        end

        sig { params(cache_key: String, cache_client: ::FeatureFlag::Cache::IMemcachedClient).void }
        def remove_cache_entry(cache_key, cache_client)
          time("feature_flag_update_processor.memcached_delete") do
            cache_client.delete(cache_key)
          end
          # Consider a delete successful if it does not raise an error.
          # This is because it will return false if not found, which is not something we consider a failure.
          success = true
        ensure
          stats.increment(
            "github.stream_processors.feature_flag_update_processor.memcached_operations",
            tags: default_stats_tags + ["operation:delete", "success:#{success == true}"]
          )
        end

        sig { params(server: String).returns(::FeatureFlag::Cache::IMemcachedClient) }
        def create_memcached_client(server)
          client = ::FeatureFlag::Cache::MemcachedClientWithoutFailover.new([server])
          # Note: This has to be configured after the client is constructed, as this logger is incompatible with the info call done in the
          # constructor of ::Memcached::Rails. Setting it after similar to how it is done for GitHub.cache (although there they use a separate initializer).
          client.logger = GitHub::Logger
          client
        end

        sig { params(message: GitHub::StreamProcessors::Message).returns(T::Hash[T.any(String, Symbol), T.untyped]) }
        def error_context_for_message(message)
          base_context = super(message)

          return base_context if message.value.nil?

          base_context.merge({
            feature_flag_name: message.value[:name],
          })
        end

        sig { returns(T::Array[String]) }
        def default_stats_tags
          stats_tags = super

          if current_message&.topic
            stats_tags << "topic:#{current_message.topic}"
          end

          stats_tags
        end

        sig { params(error: StandardError, attempts: Integer).void }
        def log_retry(error, attempts)
          context = current_error_context || {}
          context = context.merge(
            "code.namespace" => self.class.name,
            "code.function" => "retry_on_transient_errors",
            "gh.processor.name" => self.class.name,
            "gh.catalog_service" => logical_service,
            "gh.processor.retry.attempts" => attempts,
            "exception.stacktrace" => error.backtrace.to_s,
            "exception.class" => error.class.to_s
          )
          GitHub.logger.error(error, context)
        end

        sig { params(segment_name: String).returns(T::Boolean) }
        def is_default_segment_name(segment_name)
          segment_name.start_with?("_")
        end

        # Internal: Increments a counter for messages received and records the latency
        # between when the message was created and when it was received
        #
        # latency_ms - The latency between when the message was created and when it
        #              was received in milliseconds
        #
        # Returns nothing
        sig { params(latency_ms: Float).void }
        def instrument_message_received(latency_ms)
          stats.increment("github.stream_processor.message_received", tags: default_stats_tags)
          stats.timing("github.stream_processor.message_latency", latency_ms.to_i, tags: default_stats_tags)
          stats.distribution("github.stream_processor.message_latency.duration", latency_ms, tags: default_stats_tags)

          if metric_prefix
            stats.increment("#{metric_prefix}.message_received")
            stats.timing("#{metric_prefix}.latency", latency_ms.to_i)
            stats.distribution("#{metric_prefix}.latency.duration.duration", latency_ms)
          end
        end

        # Internal: Instruments the amount of time since the last heartbeat was sent
        #
        # time_since_heartbeat_ms - The amount of time since the last heartbeat was
        #                           sent in milliseconds
        #
        # Returns nothing
        sig { params(time_since_heartbeat_ms: Float).void }
        def instrument_time_since_heartbeat(time_since_heartbeat_ms)
          stats.timing("github.stream_processor.time_since_heartbeat", time_since_heartbeat_ms, tags: default_stats_tags)
          stats.distribution("github.stream_processor.time_since_heartbeat.duration", time_since_heartbeat_ms, tags: default_stats_tags)
        end
      end
    end
  end
end
