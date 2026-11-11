# typed: strict
# frozen_string_literal: true

require "github/stream_processors/transient_error_resiliency_helpers"

module Projects
  # This processor is responsible for keeping the Elasticsearch index for memex project items in sync with the
  # changes represented by the event streams it consumes.
  #
  # This processor acts as a coordinator for more detailed event-processing code that is encapsulated by the
  # `MemexProjectColumn::Interface::Indexable::Processors::Base` interface. Instances of that class are responsible for
  # subscribing to events and actually updating the Elasticsearch index, while this class layers on the following
  # characteristics:
  #
  #   1. Broadcasts of websocket messages that trigger live updates in browser clients in response to changes to
  #      Elasticsearch index.
  #   2. Automatic retries for transient errors such as high replication lag or temporary Elasticsearch
  #      unavailability.
  #   3. A full reindex of the affected project as a last resort recovery mechanism in response to a fatal error
  #      such as an unhandled exception in processing code.
  class DenormalizationProcessor < GitHub::StreamProcessors::SingleMessageProcessor
    include GitHub::StreamProcessors::TransientErrorResiliencyHelpers

    exempt_from_tenant_context_requirement
    self.rpc_instrumentation_sample_rate = 0.01

    Result = MemexProjectColumn::Interface::Indexable::Processor::Result
    ProcessedResult = MemexProjectColumn::Interface::Indexable::Processor::ProcessedResult
    FailureReason = MemexProjectColumn::Interface::Indexable::Processor::FailureReason

    FAILURE_REASON_MIXED = T.let("mixed-reasons", String)
    SKIPPABLE_FAILURE_REASONS = T.let([
      FailureReason::NO_MATCHING_DOCS,
      FailureReason::CONTENT_MISSING,
      FailureReason::MESSAGE_IGNORED
    ], T::Array[String])

    ObjectWithGlobalRelayId = T.type_alias do
      MemexProjectColumn::Interface::Indexable::Processor::Base::ObjectWithGlobalRelayId
    end

    class ProcessingError < StandardError; end
    class UpsertError < StandardError; end
    class DeleteError < StandardError; end

    class VersionConflictError < StandardError
      sig { returns(Integer) }
      attr_reader :count

      sig { params(count: Integer).void }
      def initialize(count = 0)
        super("#{count} version conflicts encountered.")
        @count = count
      end
    end

    DEFAULT_GROUP_ID = T.let("github-#{Rails.env}-projects-denormalization-processor", String)
    METRIC_PREFIX = T.let("memex.#{DEFAULT_GROUP_ID}", String)
    # All processors emit custom metrics (version_conflict, resync) under this shared
    # prefix, differentiated by a stream_processor tag. This allows a single dashboard query
    # to capture all processors without needing separate metric names.
    SHARED_METRIC_PREFIX = T.let("memex.github-#{Rails.env}-projects-denormalization-processor", String)
    LIVE_UPDATE_BASE_DATA = T.let({ type: "memex_item_denormalized_to_elasticsearch" }, T::Hash[Symbol, String])
    TRANSIENT_ERROR_RETRIES = T.let(3, Integer)
    TRANSIENT_ERROR_PAUSE_DURATION = T.let(10.seconds, ActiveSupport::Duration)
    ES_CIRCUIT_BREAKER_PAUSE_DURATION = T.let(1.minute, ActiveSupport::Duration)
    MAX_RESYNC_RETRIES = 2

    # Wait applied to the delayed live-update broadcast when at least one
    # underlying processor wrote ES with `Refresh::False` (via the
    # `:projects_processor_skip_es_refresh` flag). Must exceed the index's
    # `refresh_interval` (1s for memex_project_items) with some slack so the
    # document is guaranteed visible to search by the time the websocket
    # fires and the client refetches. See `BroadcastDenormalizedLiveUpdateJob`.
    BROADCAST_REFRESH_DELAY = T.let(1.5.seconds, ActiveSupport::Duration)

    # Identifies which topics this processor owns. Each processor skips topics
    # that don't match its key, ensuring messages are handled by exactly one consumer.
    # Override in subclasses to route to a different consumer group.
    sig { returns(MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey) }
    def self.stream_processor_key
      MemexProjectColumn::Interface::Indexable::Processor::Base::StreamProcessorKey::Default
    end

    # Returns a VexiActor for the stream processor key, which is used for feature flag targeting
    # during rollout of split-out processors.
    sig { returns(StreamProcessorKeyActor) }
    def self.stream_processor_key_actor
      StreamProcessorKeyActor.new(self.stream_processor_key)
    end

    # The split-out subclasses that the default processor still co-handles
    # during rollout. LowPriority is excluded because it is already fully
    # split.
    sig { returns(T::Array[T.class_of(DenormalizationProcessor)]) }
    def self.split_out_subclasses
      [
        DenormalizationProcessorColumnChanges,
        DenormalizationProcessorContentChangesIssue,
        DenormalizationProcessorContentChangesPullRequest,
      ]
    end


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
    options[:start_from_beginning] = false

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

    sig { params(kwargs: T.untyped).void }
    def setup(**kwargs)
      options[:group_id] ||= DEFAULT_GROUP_ID
      options[:subscribe_to] ||= begin
        topics = MemexProjectColumn::Interface::Indexable::Processor.registered_topics_for_key(self.class.stream_processor_key)
        # During rollout of split-out processors, the default processor must also
        # subscribe to their topics so it can continue handling them when the skip
        # feature flag is disabled.
        DenormalizationProcessor.split_out_subclasses.each do |c|
          topics += MemexProjectColumn::Interface::Indexable::Processor.registered_topics_for_key(c.stream_processor_key)
        end
        topics
      end
      self.metric_prefix = METRIC_PREFIX
      @transient_error_max_retries = T.let(TRANSIENT_ERROR_RETRIES, T.nilable(Integer))
    end

    sig { override.params(error: StandardError).returns(ActiveSupport::Duration) }
    private def transient_error_pause_duration(error)
      # nil or non number values will get cast to 0 via to_i, so if it's zero
      # we'll use the default
      if ENV["MEMEX_DENORMALIZATION_PAUSE_DURATION"].to_i > 0
        ENV["MEMEX_DENORMALIZATION_PAUSE_DURATION"].to_i.seconds
      elsif error.is_a?(ElastomerClient::Client::ServerError)
        ES_CIRCUIT_BREAKER_PAUSE_DURATION
      else
        TRANSIENT_ERROR_PAUSE_DURATION
      end
    end

    # This return value is ignored by the base class (and the stream processor framework
    # more generally); it is only used internally for testing.
    sig { override.params(message: GitHub::StreamProcessors::Message).returns(Result) }
    def process_message(message)
      # Each processor skips topics that don't match its stream_processor_key.
      unless MemexProjectColumn::Interface::Indexable::Processor.topic_matches_key?(
        message.topic, self.class.stream_processor_key
      )
        # For non-owned topics not in any rollout (e.g. LowPriority), skip unconditionally.
        flags = rollout_flags_for_topic(message.topic)
        unless flags
          return skip("process_message", message, "topic-not-owned-by-processor")
        end

        # During rollout of split-out processors, continue handling their topics
        # until BOTH flags are enabled — the split processor must be confirmed active
        # before the default processor stops handling its topics.
        if flags[:processor_enabled] && flags[:skip_topics]
          return skip("process_message", message, "topic-not-owned-by-processor")
        end
      end

      primary_results = T.let([], T::Array[ProcessedResult])
      secondary_results = T.let([], T::Array[ProcessedResult])
      indices = Elastomer::Indexes::MemexProjectItems.writable_indices

      # When the optimized dual-write path is enabled, build one
      # `PreconditionEvaluator` per message and thread it into every
      # per-index processor's `#consume(evaluator:)`. Cacheable gates
      # (MySQL roundtrips, `wait_for_replication!`, feature-flag checks,
      # etc.) then execute at most once per processor class per message,
      # because the evaluator memoizes outcomes keyed by
      # `(gate.name, processor.class)`. When the flag is off, `evaluator`
      # is `nil` and each processor evaluates its own chain inline via
      # `Processor::Base#consume`, preserving today's behavior.
      gate_evaluator = gate_evaluator_for(message)

      indices.each do |index|
        results = MemexProjectColumn::Interface::Indexable::Processor
          .for_message(message, index:)
          .flatten
          .each_with_object([]) do |processor, memo|
            next unless result = consume!(processor, evaluator: gate_evaluator)
            memo.concat(result)
          end

        if index.primary?
          primary_results.concat(results)
        else
          secondary_results.concat(results)
        end
      end

      if results_to_broadcast = primary_results.select(&:broadcast_result?)
        broadcast_live_update(results: results_to_broadcast, message:)
      end

      report_results(message, indices, primary_results + secondary_results)
    end

    # Returns a `PreconditionEvaluator` to share across the per-index
    # processor fan-out for this message, or `nil` when the optimized
    # dual-write feature flag is disabled.
    sig do
      params(message: GitHub::StreamProcessors::Message)
        .returns(T.nilable(MemexProjectColumn::Interface::Indexable::Processor::PreconditionEvaluator))
    end
    private def gate_evaluator_for(message)
      return unless MemexProjectColumn::Interface::Indexable::Processor::Base.optimized_dual_writes_enabled?

      MemexProjectColumn::Interface::Indexable::Processor::PreconditionEvaluator.new(message)
    end

    sig do
      params(
        processor: MemexProjectColumn::Interface::Indexable::Processor::Base,
        evaluator: T.nilable(MemexProjectColumn::Interface::Indexable::Processor::PreconditionEvaluator),
      ).returns(T.nilable(T::Array[MemexProjectColumn::Interface::Indexable::Processor::ProcessedResult]))
    end
    private def consume!(processor, evaluator: nil)
      resync_on_exception!(processor) do
        processor.consume(evaluator:).tap do
          check_for_version_conflicts!(_1)
          check_for_reportable_failures!(_1)
        end
      end
    end

    sig do
      params(
        processor: MemexProjectColumn::Interface::Indexable::Processor::Base,
        blk: T.proc.returns(T::Array[ProcessedResult])
      ).returns(T.nilable(T::Array[ProcessedResult]))
    end
    private def resync_on_exception!(processor, &blk)
      yield
    rescue MemexProjectColumn::Interface::Indexable::CanonicalDataMissingError => e
      skip("process_message", processor.message, FailureReason::CONTENT_MISSING, e)
      nil
    rescue VersionConflictError => e
      report_version_conflicts(e.count, processor)
      start_resync_job!(processor:, exception: e)
      nil
    rescue StandardError => e
      raise e if transient_error?(e)
      start_resync_job!(processor:, exception: e)
      nil
    end

    sig { params(responses: T::Array[ProcessedResult]).void }
    private def check_for_version_conflicts!(responses)
      aggregated_conflict_count = responses.sum(&:conflict_count)
      raise VersionConflictError.new(aggregated_conflict_count) if aggregated_conflict_count.positive?
    end

    sig { params(responses: T::Array[ProcessedResult]).void }
    private def check_for_reportable_failures!(responses)
      responses.each do |result|
        next if SKIPPABLE_FAILURE_REASONS.include?(result.outcome[:failure_reason])
        raise ProcessingError.new(result.outcome.to_json) if result.failures_or_errors_to_report?
      end
    end

    # Build a unique set of memex_project_ids from the results and send a live
    # update message to each of them.
    #
    # When any underlying processor wrote ES with `Refresh::False` (the
    # `:projects_processor_skip_es_refresh` flag is enabled for it), the
    # broadcast is deferred via `BroadcastDenormalizedLiveUpdateJob` with
    # `BROADCAST_REFRESH_DELAY` wait. This ensures the websocket fires after
    # the next ES periodic refresh so client refetches see fresh data
    # instead of racing the refresh interval. Non-flagged messages continue
    # to broadcast inline for minimum latency.
    sig { params(results: T::Array[ProcessedResult], message: GitHub::StreamProcessors::Message).void }
    private def broadcast_live_update(results:, message:)
      return if results.empty?

      project_ids = T.let(Set.new, T::Set[Integer])
      updated_models = T.let(Set.new, T::Set[ObjectWithGlobalRelayId])
      any_skipped_es_refresh = T.let(false, T::Boolean)

      results.flatten.each do |result|
        next if result.failed?
        project_ids.merge(result.updated_memex_ids)
        updated_models.merge(result.updated_models.flatten)
        any_skipped_es_refresh = true if result.skipped_es_refresh?
      end

      memex_project_ids = project_ids.to_a
      updated_models_array = updated_models.to_a
      timestamp = message.timestamp.to_i
      source_topic = message.topic
      request_id = message.dig(:request_context, :request_id).presence

      if any_skipped_es_refresh
        # ActiveJob serializes job arguments via JSON, which rejects Integer
        # hash keys outright (raises ActiveJob::SerializationError). Stringify
        # the per-project map at the enqueue boundary; `BroadcastDenormalizedLiveUpdateJob#perform`
        # already normalizes back to Integer (`project_id.to_i`) on the receive
        # side, so the round-trip is invariant.
        items_by_project = MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster
          .extract_items_by_project(updated_models_array)
          .transform_keys(&:to_s)

        BroadcastDenormalizedLiveUpdateJob
          .set(wait: BROADCAST_REFRESH_DELAY)
          .perform_later(
            memex_project_ids:,
            timestamp:,
            source_topic:,
            model_gids: MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster.extract_model_gids(updated_models_array),
            items_by_project:,
            request_id:,
          )
      else
        MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster.call(
          memex_project_ids:,
          timestamp:,
          source_topic:,
          updated_models: updated_models_array,
          request_id:,
        )
      end
    end

    sig do
      params(
        message: GitHub::StreamProcessors::Message,
        indices: T::Array[Elastomer::Indexes::MemexProjectItems],
        results: T::Array[ProcessedResult]
      ).returns(Result)
    end
    private def report_results(message, indices, results)
      # If failures are reported here, we assume they are safe to skip
      # Failures requiring retries are handled in consume!
      skip_reasons = results.filter_map { _1.outcome[:failure_reason] if _1.failed? }
      if skip_reasons.size == results.size
        unique_reasons = skip_reasons.uniq
        return skip("process_message", message, FAILURE_REASON_MIXED) if unique_reasons.size > 1
        return skip("process_message", message, unique_reasons.first) if unique_reasons.size == 1
      end

      GitHub.logger.info(
        "Processed message successfully",
        {
          "code.namespace" => self.class.name,
          "code.function" => "report_results",
          "message.timestamp" => message.timestamp,
          "gh.memex.denormalization_processor.indices" => indices.map(&:name).sort,
        }.merge(error_context_for_message(message))
      )

      message.success
      Result::Success.new
    end

    sig do
      params(
        conflict_count: Integer,
        processor: MemexProjectColumn::Interface::Indexable::Processor::Base,
      )
      .void
    end
    private def report_version_conflicts(conflict_count, processor)
      conflict_scope = case conflict_count
      when 1 then "S"
      when 2..10 then "M"
      when 11..100 then "L"
      else "XL"
      end
      GitHub.dogstats.increment(
        "#{SHARED_METRIC_PREFIX}.version_conflict", tags: [
          "processor:#{self.class.name&.underscore}",
          "topic:#{processor.message.topic}",
          "scope:#{conflict_scope}",
          "index:#{processor.index.name}",
          "field_processor": processor.class.name&.demodulize.underscore
        ]
      )
    end

    sig do
      params(
        fn: String,
        message: GitHub::StreamProcessors::Message,
        reason: String,
        error: T.nilable(StandardError)
      )
      .returns(Result::Skip)
    end
    private def skip(fn, message, reason, error = nil)
      message.skip(reason)
      Result::Skip.new(reason)
    end

    # Returns the rollout flags hash for a topic that belongs to a subclass processor,
    # or nil if no subclass claims the topic. The subclass lookup is memoized per topic;
    # the flag checks are not.
    sig { params(topic: String).returns(T.nilable({ processor_enabled: T::Boolean, skip_topics: T::Boolean })) }
    private def rollout_flags_for_topic(topic)
      actor = split_processor_actor_for_topic(topic)
      return nil unless actor

      {
        processor_enabled: FeatureFlag.vexi.enabled?(:memex_denormalization_split_processor_enabled, actor, default: false),
        skip_topics: FeatureFlag.vexi.enabled?(:memex_denormalization_split_processor_skip_topics, actor, default: false),
      }
    end

    # Memoizes which subclass processor (if any) owns the given topic, returning its
    # StreamProcessorKeyActor or nil.
    sig { params(topic: String).returns(T.nilable(StreamProcessorKeyActor)) }
    private def split_processor_actor_for_topic(topic)
      @split_processor_actor_cache = T.let(@split_processor_actor_cache, T.nilable(T::Hash[String, T.nilable(StreamProcessorKeyActor)]))
      @split_processor_actor_cache ||= {}

      if @split_processor_actor_cache.key?(topic)
        return @split_processor_actor_cache[topic]
      end

      result = T.let(nil, T.nilable(StreamProcessorKeyActor))
      DenormalizationProcessor.split_out_subclasses.each do |c|
        if MemexProjectColumn::Interface::Indexable::Processor.topic_matches_key?(topic, c.stream_processor_key)
          result = c.stream_processor_key_actor
          break
        end
      end

      @split_processor_actor_cache[topic] = result
    end

    sig do
      params(
        processor: MemexProjectColumn::Interface::Indexable::Processor::Base,
        exception: StandardError,
        project_ids_to_resync: T.nilable(T::Array[Integer]),
        tries_remaining: Integer
      )
      .void
    end
    private def start_resync_job!(
      processor:,
      exception:,
      project_ids_to_resync: nil,
      tries_remaining: MAX_RESYNC_RETRIES
    )
      project_ids_to_resync ||= processor.project_ids_to_resync_on_failure

      # Some volume of `VersionConflictError`s are expected, so we don't report them as exceptions.
      # Instead, we count them below via Datadog metric, and use that to detect anomalies.
      unless exception.is_a?(VersionConflictError)
        Failbot.report!(
          exception,
          {
            "processor" => self.class.name,
            "code.namespace" => self.class.name,
            "code.function" => "start_resync_job!",
            "elasticsearch.index" => processor.index.name,
            "gh.memex.denormalization_processor.project_ids_to_resync" => project_ids_to_resync,
          }.merge(error_context_for_message(processor.message))
        )
      end

      return if project_ids_to_resync.blank?

      GitHub.dogstats.increment(
        "#{SHARED_METRIC_PREFIX}.resync",
        tags: [
          "processor:#{self.class.name&.underscore}",
          "error:#{exception.class.name}",
          "topic:#{processor.message.topic}",
          "index:#{processor.index.name}",
        ]
      )

      failed_project_ids = MemexProject::ResyncItems.resync_later(project_ids_to_resync, indices: [processor.index])

      return unless failed_project_ids.present?

      raise exception unless tries_remaining > 0

      start_resync_job!(
        processor:,
        exception:,
        project_ids_to_resync: failed_project_ids,
        tries_remaining: tries_remaining - 1
      )
    end

    # Workaround for https://github.com/sorbet/sorbet/issues/5025
    include GitHub::StreamProcessors::TransientErrorResiliency
  end
end
