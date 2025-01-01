# typed: strict
# frozen_string_literal: true

module GitHub
  module StreamProcessors
    module FeatureManagement
      class FeatureFlagUpdateProcessor < BaseProcessor
        extend T::Sig
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

        DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-feature_flag_data_processor", String)
        DEFAULT_SUBSCRIBE_TO = T.let([
          /featureflags\.data\.v0\.FeatureFlag\Z/,
          /featureflags\.data\.v0\.Segment\Z/,
        ], T::Array[Regexp])


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

        sig { params(group_id: T.nilable(String), subscribe_to: T.nilable(String), rescue_from_standard_error: T::Boolean, kwargs: T.untyped).void }
        def initialize(group_id: nil, subscribe_to: nil, rescue_from_standard_error: Rails.env.production?, **kwargs)
          # Define these here so Sorbet doesn't complain
          @memcached_servers = T.let([], T::Array[String])
          @memcached_clients = T.let([], T::Array[GitHub::Cache::Client])

          super
        end

        # Public: Configure the Hydro processor
        sig { params(kwargs: T.untyped).void }
        def setup(**kwargs)
          options[:group_id] ||= DEFAULT_GROUP_ID
          options[:subscribe_to] ||= DEFAULT_SUBSCRIBE_TO

          partition = memcached_partition
          @memcached_servers = servers_for_partition(partition)
          @memcached_clients = create_memcached_clients(GitHub.site, @memcached_servers, partition)
        end

        # Public: Process a single Hydro message
        #
        # message - The Hydro message to process
        #
        # Returns nothing
        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_message(message)
          return message.skip("feature flag disabled") if GitHub.flipper[:feature_flag_update_processor_disabled].enabled?

          if message.topic == "featureflags.data.v0.FeatureFlag"
            process_feature_flag_message(message)
          elsif message.topic == "featureflags.data.v0.Segment"
            process_segment_message(message)
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

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_feature_flag_message(message)
          if message.value.present?
            add_feature_flag_entry(message)
          else
            remove_feature_flag_entry(message)
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def process_segment_message(message)
          if message.value.present?
            add_segment_entry(message)
          else
            remove_segment_entry(message)
          end
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def add_feature_flag_entry(message)
          feature_flag_name = message.value[:name]
          cache_key = "vexi:ff:#{feature_flag_name}"
          feature_flag = Vexi::FeatureFlag.from_json(message.value.stringify_keys)

          set_cache_entry(cache_key, Vexi::FeatureFlag.to_h(feature_flag))
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def add_segment_entry(message)
          segment_name = message.value[:name]
          cache_key = "vexi:sg:#{segment_name}"
          segment = Vexi::Segment.new.tap do |s|
            s.name = segment_name
            s.actors = Vexi::HashActorCollection.new(message.value[:actors])
          end

          set_cache_entry(cache_key, {
            "name" => segment.name,
            "actors" => segment.actors.keys.sort,
          })
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def remove_feature_flag_entry(message)
          cache_key = "vexi:ff:#{message.key}"
          remove_cache_entry(cache_key)
        end

        sig { params(message: GitHub::StreamProcessors::Message).void }
        def remove_segment_entry(message)
          cache_key = "vexi:sg:#{message.key}"
          remove_cache_entry(cache_key)
        end

        sig { params(cache_key: String, content: T.untyped).void }
        def set_cache_entry(cache_key, content)
          payload = GitHub::Cache::Codec.pack(content)

          @memcached_clients.each do |client|
            client.set(cache_key, payload, 1.day, true)
          end
        end

        sig { params(cache_key: String).void }
        def remove_cache_entry(cache_key)
          @memcached_clients.each do |client|
            client.delete(cache_key)
          end
        end

        sig { returns(Symbol) }
        def memcached_partition
          # Returns global partition for GHES or Proxima
          return :global if GitHub.single_or_multi_tenant_enterprise?

          :featureflag
        end

        sig { params(site: String, servers: T::Array[String], partition: Symbol).returns(T::Array[GitHub::Cache::Client]) }
        def create_memcached_clients(site, servers, partition)
          config = GitHub.cache_config

          servers.map do |server|
            GitHub::Cache::Client.new(config).tap do |c|
              c.current_partition = partition
              # We're only going to update a single server in a stream processor instance
              c.set_runtime_servers([server])
            end
          end
        end

        sig { params(partition: Symbol).returns(T::Array[String]) }
        def servers_for_partition(partition)
          # Enterprise environments will return the global memcached servers
          if partition == :global
            Array(GitHub.cache_config.fetch(:servers))
          else
            GitHub.partition_config.fetch(partition).fetch("servers")
          end
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
            "exception.stacktrace" => error.backtrace.to_s
          )
          GitHub.logger.error(error, context)
        end
      end
    end
  end
end
