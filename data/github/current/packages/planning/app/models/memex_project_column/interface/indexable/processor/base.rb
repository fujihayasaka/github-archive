# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Interface::Indexable
  module Processor
    # This is the interface for classes that are responsible for copying data for a field supported in GitHub Projects
    # from its canonical source to the Elasticsearch cluster that we use to serve read requests. Subclasses of this
    # base class are attached to specific fields via the `Indexable#register_processors` method, which is typically
    # implemented by a subclass of `MemexProjectColumn::Field::Base`.
    #
    # The purpose of this interface is to abstract away underyling event-processing infrastructure and resilience
    # logic from the implementor. As a result the implementor should be able to focus on just the following domain
    # logic, which is implemented via abstract methods in this class:
    #
    #   1. Telling us which Hydro events we should listen for when updating this field's data. It is the implementors
    #      reponsibility to figure out which events are relevant, and to add missing events if necessary. For more
    #      information on Hydro events, see:
    #      https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/
    #
    #   2. Telling us which events we can safely ignore. This can happen due to the event payload being invalid, or
    #      the appropriate data being missing from either the canonical source for that data (e.g MySQL) or the
    #      Elasticsearch index.
    #
    #   3. Updating the Elasticsearch index appropriately with the data from the canonical source. It is the
    #      implementor's responsibility to retrieve the canonical data using identifiers in the event payload, and to
    #      issue the appropriate update commands to the Elasticsearch API.
    #
    # Please see the documentation for each abstract or overridable method below for more details on how to implement
    # each of these responsibilities.
    #
    # If you are implementing a processor for a generic field type, then you should include the
    # `GenericFieldUpdateStrategy` module in your subclass. That module simplifies this interface considerably.
    #
    # Note that in the documentation below the term "event" is synonmous with the term "message": both refer to a
    # Hydro event.
    class Base
      extend T::Helpers
      include GitHub::Memoizer
      include GitHub::Tracing

      METRIC_NAME_INDEX_TIME = T.let("memex.indexable.processor.index_time", String)
      DEFAULT_MAX_ASSOCIATIONS = 1000
      METRIC_NAME_INDEX_DURATION_BY_ASSOCIATION_COUNT = T.let("memex.indexable.processor.index_duration_by_association_count", String)

      # Vexi flag (gated via `processor_class_actor`) that opts a processor
      # into using `Elastomer::Interfaces::Api::*::Request::Params::Refresh::False`
      # for its Elasticsearch writes instead of the legacy `True`/`WaitFor`
      # value. Processors opt in by calling `skip_es_refresh?` when building
      # their refresh param. See the helper for details.
      SKIP_REFRESH_FEATURE_FLAG = T.let(:projects_processor_skip_es_refresh, Symbol)

      # Dogstats counter incremented once per processor instance when
      # `skip_es_refresh?` first returns true. Tagged with the processor
      # subclass so we can watch rollout per processor. Useful for confirming
      # the flag is actually flipping in production.
      METRIC_NAME_SKIPPED_ES_REFRESH = T.let("memex.indexable.processor.skipped_es_refresh", String)

      abstract!

      GenericHash = T.type_alias { T::Hash[T.untyped, T.untyped] }
      NilableGenericHash = T.type_alias { T.nilable(GenericHash) }

      # An Object that responds to `global_relay_id`.
      ObjectWithGlobalRelayId = T.type_alias { Object }

      class RefreshParamValue < T::Enum
        enums do
          True = new "true"
          False = new "false"
          WaitFor = new "wait_for"
        end
      end

      class UpdateByQueryRefreshParamValue < T::Enum
        enums do
          True = new "true"
          False = new "false"
        end
      end

      sig { returns(GitHub::StreamProcessors::Message) }
      attr_reader :message

      sig { returns(Elastomer::Indexes::MemexProjectItems) }
      attr_reader :index

      sig { returns(Search::Memex::Client) }
      attr_reader :es_client
      private :es_client

      class UnprocessableMessageError < StandardError; end

      # The list of Hydro events that will be routed to this processor.
      #
      # In order to control the complexity of the logic used to implement the other methods of this interface, we
      # recommend that you only subscribe to few events here (ideally only one), but that you create multiple
      # `Indexable::Processor::Base` subclasses that together cover all the events that might change data for this
      # field. The `Indexable::Processors::SingleSelect*`` classes give a good example of this pattern.
      #
      # You can read through a list of existing events that you might want to use here in the event catalog:
      # https://hydro.githubapp.com/event_catalog/hydro
      #
      # If you cannot find a relevant event in the catalog, you can add a new event by following this guide:
      # https://thehub.github.com/epd/engineering/products-and-services/internal/hydro/guides/adding-a-new-event/
      #
      # EXAMPLE:
      #
      #   def self.topics
      #     [
      #       /github\.v1\.IssueUpdateAssignee\Z/
      #     ]
      #   end
      sig { abstract.returns(T::Array[Regexp]) }
      def self.topics; end

      # Determines which denormalization processor consumer group handles this processor's topics.
      # Override in subclasses to route to a different consumer group.
      # Processors with the Default key are handled by the standard DenormalizationProcessor.
      class StreamProcessorKey < T::Enum
        enums do
          Default = new("default")
          LowPriority = new("low_priority")
          ContentChangesIssue = new("content_changes_issue")
          ContentChangesPullRequest = new("content_changes_pull_request")
          ColumnChanges = new("column_changes")
        end
      end

      sig { overridable.returns(StreamProcessorKey) }
      def self.stream_processor_key
        StreamProcessorKey::Default
      end

      sig do
        params(
          message: GitHub::StreamProcessors::Message,
          index: Elastomer::Indexes::MemexProjectItems,
        )
        .void
      end
      def initialize(message, index:)
        @message = message
        @index = index
        @es_client = T.let(Search::Memex::Client.new(@index), Search::Memex::Client)
        @started_at_by_method_name = T.let({}, T::Hash[Symbol, T.untyped])
      end

      # This is the first of multiple gates that allow a processor to skip a message before consuming resources
      # unnecessarily.
      #
      # This gate gives the consumer an opportunity to skip a message based purely on the message payload. This can
      # be used to verify that attributes of the payload that are necessary for further processing are actually
      # present. Access to the message is provided via the `message` attr_reader.
      #
      # EXAMPLE:
      #
      #   def valid_message?
      #     return message.dig(:project, :id).present?
      #   end
      sig { overridable.returns(T::Boolean) }
      def valid_message?
        true
      end

      # This is the second gate that allows a processor to skip a message before consuming resources unnecessarily.
      #
      # This gate should be used to check that there is at least one document in the Elasticsearch index that can be
      # identified from the attributes in the message payload and that in fact needs to be updated. Access to the
      # Elasticsearch index/API is provided via the `index` attr_reader.
      #
      # This method should not make any MySQL requests.
      #
      # EXAMPLE:
      #
      #   def matching_elasticsearch_documents?
      #     response = index.docs.get(
      #       id: message.dig(:item, :id),
      #       routing: message.dig(:project, id),
      #       _source: false
      #     )
      #     response["found"] == true
      #   end
      sig { abstract.returns(T::Boolean) }
      def matching_elasticsearch_documents?; end

      # This is the third and final gate that allows a processor to skip a message before consuming resources
      # unnecessarily.
      #
      # This gate should be used to check that data we want to write to Elasticsearch has not been deleted while the
      # event we are processing was queued. We perform this check to guard against race conditions that our
      # infrastructure cannot prevent.
      #
      # This method typically checks that relevant data is still present in MySQL. Assuming that
      # `dependent_mysql_replication_cluster` returns a non-nil value, the framework will guarantee that the
      # implementor of this method does not need to worry about MySQL replication lag.
      #
      # EXAMPLE:
      #
      #   def canonical_data_present?
      #     Issue.find_by(id: message.dig(:item, :content_id)).present?
      #   end
      sig { abstract.returns(T::Boolean) }
      def canonical_data_present?; end

      # For fields that store their data in MySQL cluster that is accessible from the monolith, this method should
      # return the name of the MySQL cluster in which the data is stored.
      #
      # For fields that do not store data in MySQL, this method should return nil.
      #
      # EXAMPLE:
      #
      #  def dependent_mysql_replication_cluster
      #    Issue.cluster_name
      #  end
      sig { abstract.returns(T.nilable(Symbol)) }
      def dependent_mysql_replication_cluster; end

      # This method should be used to update the Elasticsearch index with the latest data for this field.
      #
      # Implementors must ensure that this method is as targeted and efficient as possible. Most often that means
      # that the this method should use the Elasticsearch update API with a request that is restricted to a single
      # document and issued with a routing value. For more details on that API see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update.html
      #
      # When you must update multiple documents, we recommend that you use the update_by_query
      # or delete_by_query APIs, with special attention taken to limit the scope of the query as much as possible.
      # For more details on these APIs see:
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-update-by-query.html
      # https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-delete-by-query.html
      #
      # Access to the Elasticsearch index/API is provided via the `es_client` parameter.
      #
      # This method should return the response from the Elasticseach write request.
      #
      # EXAMPLE:
      #
      #   def update(es_client)
      #     body = Elastomer::Interfaces::Api::Update::Request::Body.new(doc: {foo: "bar"}})
      #     params = Elastomer::Interfaces::Api::Update::Request::Params.new(id: message.dig(:item, :id))
      #     es_client.update(body, params)
      #   end
      #
      #   def update(es_client)
      #     project_ids = project_ids_to_resync
      #     failed_project_ids = resync_with_retries(project_ids:)
      #     ResyncProjectsResult.new(updated_memex_ids: project_ids - failed_project_ids)
      #   end
      sig do abstract
        .params(es_client: Search::Memex::Client)
        .returns(T.any(ResyncProjectsResult, Search::Memex::Client::Response, T::Array[Search::Memex::Client::Response]))
      end
      def update(es_client); end

      # When a message fails to be processed, we will fall back to the last-resort measure of resyncing the entire
      # project(s) that a given message would have affected.
      #
      # This method should return an array of ids for those projects so that the framework can queue the appropriate
      # resync jobs.
      sig { abstract.returns(T::Array[Integer]) }
      def project_ids_to_resync_on_failure; end

      # The method should return an array of ActiveRecord models that were updated as a result of the message being
      # processed. Global ID's are extracted from models that support GitHub::Relay::GlobalIdentification and
      # then returned from live updates broadcaster for clients to know which models to refetch.
      sig { abstract.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models; end

      # Override this method to return false whenever you do not want to broadcast a live update for a particular
      # message.
      #
      # This hint will only be respected if no other processor returns `true` from this method for the same message.
      sig { overridable.returns(T::Boolean) }
      def broadcast_result? = true

      # Override this method to return additional key-value pairs that will be included as tags on the
      # `index_time` metric and as span attributes for the `_update` trace. This is useful for A/B experiments
      # where a processor wants to tag metrics with the variant that was used.
      #
      # This method is conceptually private, but cannot be marked `private` due to its use in the `trace_method`
      # configuration.
      sig { overridable.returns(T::Hash[String, String]) }
      def update_extra_tags
        {}
      end

      # Override this method to check whether the number of associated records exceeds `max_associations`.
      # When `true`, the message will be skipped to avoid head-of-line blocking caused by extremely large
      # associations (e.g. hundreds of thousands of review requests).
      #
      # Implementations should use `.offset(max_associations).exists?` so that MySQL only needs to verify
      # a row exists beyond the offset rather than counting all matching rows.
      #
      # Return `nil` to opt out of the threshold check (the default behavior).
      sig { overridable.returns(T.nilable(T::Boolean)) }
      def exceeds_max_associations?; end

      # Override this method to customize the maximum number of associations allowed before a message is
      # skipped. The default is `DEFAULT_MAX_ASSOCIATIONS` (1000).
      sig { overridable.returns(Integer) }
      def max_associations
        DEFAULT_MAX_ASSOCIATIONS
      end

      # Override this method to return additional feature flag actors specific to the processor subclass.
      # Actors must be string representations (e.g. "Issue:123") and must not load ActiveRecord objects.
      # These actors are combined with the common actors extracted from the message payload.
      #
      # NOTE: Because actors are passed as plain string identifiers (not ActiveRecord objects), many
      # custom gates (e.g. staff ship) will not work with these flags. Only gates that operate on the
      # raw actor string are supported.
      #
      # EXAMPLE:
      #
      #   def feature_flag_actors
      #     milestone_id = message.dig(:milestone, :id)
      #     [
      #       ("Milestone:#{milestone_id}" if milestone_id.present?),
      #     ].compact
      #   end
      sig { overridable.returns(T::Array[String]) }
      def feature_flag_actors
        []
      end

      # Returns a vexi actor representing this processor's subclass, so feature
      # flags can be targeted at all instances of a particular processor class
      # via a single shared flag name. Mirrors the `ActiveJob::JobClassActor`
      # pattern used by `ApplicationJob#job_class_actor`.
      sig { returns(ClassActor) }
      def self.processor_class_actor
        ClassActor.new(self)
      end

      sig { returns(ClassActor) }
      def processor_class_actor
        self.class.processor_class_actor
      end

      # Returns whether the `projects_any_match_helper` feature flag is enabled
      # for this processor's subclass. When enabled, processors should prefer
      # `Search::Memex::Client#any_match?` over `index.count_all(...) > 0`
      # inside `matching_elasticsearch_documents?`.
      sig { returns(T::Boolean) }
      def any_match_helper_enabled?
        FeatureFlag.vexi.enabled?(:projects_any_match_helper, processor_class_actor, default: false)
      end

      # Returns whether this processor should use
      # `Elastomer::Interfaces::Api::*::Request::Params::Refresh::False` in
      # place of its legacy `True`/`WaitFor` refresh value, based on the
      # `SKIP_REFRESH_FEATURE_FLAG` evaluated against this processor's
      # `processor_class_actor`. Memoized per-processor-instance so the vexi
      # lookup is paid at most once per consumed message.
      #
      # Prefer calling one of the `*_refresh_strategy` methods at ES-write
      # call sites — this method is exposed mainly so the strategies can
      # share a single flag check. When this method first returns true for
      # a given processor instance, it also increments
      # `METRIC_NAME_SKIPPED_ES_REFRESH` so we can monitor rollout per
      # processor subclass.
      sig { returns(T::Boolean) }
      memoize private def skip_es_refresh?
        enabled = FeatureFlag.vexi.enabled?(SKIP_REFRESH_FEATURE_FLAG, processor_class_actor, default: false)
        if enabled
          GitHub.dogstats.increment(
            METRIC_NAME_SKIPPED_ES_REFRESH,
            tags: ["processor:#{processor_subclass_name}"],
          )
        end
        enabled
      end

      # Refresh value to use when this processor calls `es_client.update`.
      # Returns `Refresh::False` when the skip-refresh flag is enabled for
      # this processor; otherwise the legacy `Refresh::WaitFor`. Override
      # in a subclass to supply a different legacy default (e.g.
      # `ProcessProjectItem` uses `Refresh::True`).
      sig { overridable.returns(Elastomer::Interfaces::Api::Update::Request::Params::Refresh) }
      def update_refresh_strategy
        if skip_es_refresh?
          Elastomer::Interfaces::Api::Update::Request::Params::Refresh::False
        else
          Elastomer::Interfaces::Api::Update::Request::Params::Refresh::WaitFor
        end
      end

      # Refresh value to use when this processor calls
      # `es_client.update_by_query`. Returns `Refresh::False` under the flag,
      # `Refresh::True` otherwise (matching the legacy client default for
      # this API). Override to customize per-processor.
      sig { overridable.returns(Elastomer::Interfaces::Api::UpdateByQuery::Request::Params::Refresh) }
      def update_by_query_refresh_strategy
        if skip_es_refresh?
          Elastomer::Interfaces::Api::UpdateByQuery::Request::Params::Refresh::False
        else
          Elastomer::Interfaces::Api::UpdateByQuery::Request::Params::Refresh::True
        end
      end

      # Refresh value to use when this processor calls `es_client.bulk`.
      # Returns `Refresh::False` under the flag, `Refresh::WaitFor` otherwise.
      # Override to customize per-processor.
      sig { overridable.returns(Elastomer::Interfaces::Api::Bulk::Request::Params::Refresh) }
      def bulk_refresh_strategy
        if skip_es_refresh?
          Elastomer::Interfaces::Api::Bulk::Request::Params::Refresh::False
        else
          Elastomer::Interfaces::Api::Bulk::Request::Params::Refresh::WaitFor
        end
      end

      # Refresh value to use when this processor calls `es_client.delete`.
      # Returns `Refresh::False` under the flag, `Refresh::WaitFor` otherwise.
      # Override to customize per-processor.
      sig { overridable.returns(Elastomer::Interfaces::Api::Delete::Request::Params::Refresh) }
      def delete_refresh_strategy
        if skip_es_refresh?
          Elastomer::Interfaces::Api::Delete::Request::Params::Refresh::False
        else
          Elastomer::Interfaces::Api::Delete::Request::Params::Refresh::WaitFor
        end
      end

      # Processes the message through the precondition chain and, on
      # allow, applies the update to Elasticsearch.
      #
      # Two execution paths are available:
      #
      # * **`evaluator: nil` (default, legacy path):** the precondition
      #   chain is inlined here, gate-by-gate. This is what runs whenever
      #   the orchestrator hasn't opted into the optimized dual-write path.
      # * **`evaluator:` supplied (optimized path):** the chain is walked
      #   by the supplied `PreconditionEvaluator`, which
      #   `Projects::DenormalizationProcessor` constructs once per message
      #   and shares across the per-index processor fan-out so cacheable
      #   gates execute at most once per processor class per message.
      sig do
        params(evaluator: T.nilable(PreconditionEvaluator))
          .returns(T::Array[ProcessedResult])
      end
      def consume(evaluator: nil)
        if evaluator
          decision = evaluator.run(processor: self)
          return failure(T.must(decision.reason)) unless decision.allowed?
        else
          return failure(FailureReason::MESSAGE_IGNORED) unless _valid_message?
          return failure(FailureReason::FEATURE_FLAG_SKIPPED) if _feature_flag_skips_message?
          return failure(FailureReason::NO_MATCHING_DOCS) unless _matching_elasticsearch_documents?
          return failure(FailureReason::MAX_ASSOCIATIONS_EXCEEDED) if _max_associations_exceeded?
          return failure(FailureReason::CONTENT_MISSING) unless _canonical_data_present?
        end

        if FeatureFlag.vexi.enabled?(:memex_instrument_association_counts, default: false)
          with_association_timings(self.class.tracked_associations) { _update }
        else
          _update
        end
      end

      # The precondition chain for this processor, in cheap → expensive
      # order. Walked by `PreconditionEvaluator#run`, which invokes each
      # gate's `allowed` lambda (or replays a memoized outcome for cacheable
      # gates).
      #
      # Order must match the inline chain in `#consume` so the
      # `evaluator:`-supplied and `evaluator: nil` paths produce identical
      # decisions for a given message.
      sig { returns(T::Array[PreconditionEvaluator::Gate]) }
      def precondition_gates
        [
          PreconditionEvaluator.truthy_gate(
            predicate: method(:_valid_message?),
            failure_reason: FailureReason::MESSAGE_IGNORED,
            cacheable: true,
          ),
          PreconditionEvaluator.falsy_gate(
            predicate: method(:_feature_flag_skips_message?),
            failure_reason: FailureReason::FEATURE_FLAG_SKIPPED,
            cacheable: true,
          ),
          PreconditionEvaluator.truthy_gate(
            predicate: method(:_matching_elasticsearch_documents?),
            failure_reason: FailureReason::NO_MATCHING_DOCS,
            cacheable: false,
          ),
          PreconditionEvaluator.falsy_gate(
            predicate: method(:_max_associations_exceeded?),
            failure_reason: FailureReason::MAX_ASSOCIATIONS_EXCEEDED,
            cacheable: true,
          ),
          PreconditionEvaluator.truthy_gate(
            predicate: method(:_canonical_data_present?),
            failure_reason: FailureReason::CONTENT_MISSING,
            cacheable: true,
          ),
        ]
      end

      # Whether the optimized dual-write path is enabled. Consulted by the
      # orchestrator (`Projects::DenormalizationProcessor`) when deciding
      # whether to construct and thread a shared `PreconditionEvaluator`
      # into each processor's `#consume(evaluator:)`. `#consume` itself
      # branches purely on the presence of the `evaluator:` argument.
      sig { returns(T::Boolean) }
      def self.optimized_dual_writes_enabled?
        FeatureFlag.vexi.enabled?(:projects_denormalization_processor_optimized_dual_writes, default: false)
      end

      # Subclasses override this to return the AR model names to track during _update.
      # By default no instrumentation overhead is incurred.
      sig { overridable.returns(T.nilable(T::Set[String])) }
      def self.tracked_associations; end

      sig { params(failure_reason: String).returns(T::Array[ProcessedResult]) }
      private def failure(failure_reason)
        Array(ProcessedResult.new(failure_reason:))
      end

      # This wrapper is necessary for the `trace_method` macro. Without it, each subclass would have to do its own
      # instrumentation for the overidden `valid_message?` method.
      sig { returns(T::Boolean) }
      private def _valid_message?
        valid_message?
      end

      # This gate checks whether the current message should be skipped based on a per-processor feature flag.
      # The flag name is derived from the processor class name. The flag is checked against a set of
      # string-based actors extracted from the message payload. If the flag is enabled for any actor,
      # the message is skipped.
      #
      # The flag defaults to `false` (not skipped). To skip messages for a specific actor, enable the
      # flag for that actor string (e.g. "Repository:123").
      sig { returns(T::Boolean) }
      private def _feature_flag_skips_message?
        actors = (common_feature_flag_actors + feature_flag_actors).compact_blank.uniq
        return false if actors.empty?

        FeatureFlag.vexi.enabled?(skip_message_feature_flag_name, actors, default: false)
      end

      # Returns the feature flag name used to skip messages for this processor.
      # Derived from the processor subclass name, e.g. MilestoneDelete becomes
      # "projects_milestone_delete_indexable_processor_skip_message".
      sig { returns(String) }
      private def skip_message_feature_flag_name
        "projects_#{processor_subclass_name}_indexable_processor_skip_message"
      end

      # Extracts common entity identifiers from the message payload as string-based feature flag actors.
      # These actors are available across most Hydro event types consumed by indexable processors.
      # No ActiveRecord objects are loaded — only raw string construction from message primitives.
      sig { returns(T::Array[String]) }
      private def common_feature_flag_actors
        actor_id = message.dig(:actor, :id)
        repository_id = message.dig(:repository, :id) || message.dig(:repository_id)
        issue_id = message.dig(:issue, :id_value) || message.dig(:issue_id)
        pull_request_id = message.dig(:pull_request, :id)
        project_id = message.dig(:memex_project, :id) || message.dig(:project, :id)

        [
          ("User:#{actor_id}" if actor_id.present?),
          ("Repository:#{repository_id}" if repository_id.present?),
          ("Issue:#{issue_id}" if issue_id.present?),
          ("PullRequest:#{pull_request_id}" if pull_request_id.present?),
          ("MemexProject:#{project_id}" if project_id.present?),
        ].compact
      end

      # This wrapper is necessary for the `trace_method` macro. Without it, each subclass would have to do its own
      # instrumentation for the overidden `matching_elasticsearch_documents?` method.
      sig { returns(T::Boolean) }
      private def _matching_elasticsearch_documents?
        matching_elasticsearch_documents?
      end

      # This gate checks whether the association count for the message exceeds the processor's limit.
      # Processors opt in by overriding `exceeds_max_associations?` to return a non-nil value. When the
      # check returns `true`, the message is skipped and telemetry is emitted.
      #
      # Short-circuits to `false` when the `:memex_max_associations_constraint`
      # feature flag is disabled, so callers don't have to gate this themselves
      # (and overrides that issue MySQL queries from `exceeds_max_associations?`
      # do not run unnecessarily).
      sig { returns(T::Boolean) }
      private def _max_associations_exceeded?
        return false unless max_associations_constraint_enabled?

        exceeded = exceeds_max_associations?
        return false if exceeded.nil?

        if exceeded
          GitHub.logger.info(
            "Skipping message due to associations exceeding max_associations",
            processor: processor_subclass_name,
            max_associations: max_associations,
            index: index.name,
            issue_id: message.dig(:issue, :id_value) || message.dig(:issue_id),
            pull_request_id: message.dig(:pull_request, :id),
          )
        end

        exceeded
      end

      sig { returns(T::Boolean) }
      private def _canonical_data_present?
        wait_for_replication!
        canonical_data_present?
      end

      sig { returns(T::Array[ProcessedResult]) }
      private def _update
        Array.wrap(update(@es_client)).flat_map do |result|
          case result
          when ProcessedResult
            result
          else
            response = ElasticsearchUpdateResponse.new(data: result&.to_hash)
            ProcessedResult.new(
              topic: message.topic,
              elasticsearch_update_response: response,
              updated_memex_ids: project_ids_to_resync_on_failure,
              updated_models: updated_models,
              broadcast_result: broadcast_result?,
              skipped_es_refresh: skip_es_refresh?,
            )
          end
        end
      end

      sig { returns(T.nilable(String)) }
      protected def document_type
        # The document type parameter requirement was removed in ES7
        index.index_running_version_8_plus? ? nil : Elastomer::Adapters::MemexProjectItem.document_type
      end

      sig { void }
      private def wait_for_replication!
        return unless cluster = self.dependent_mysql_replication_cluster

        WaitForReplication.new(
          format_time_for_replication(message.timestamp),
          store_name: cluster,
          max_wait_seconds: 8
        ).wait!
      end

      # WaitForReplication expects a specific Timestamp format. This first
      # converts Rational to time, and then passes it into
      # the method that converts it into the format WaitForReplication is
      # expecting.
      sig { params(timestamp: T.any(Rational, Integer)).returns(Integer) }
      private def format_time_for_replication(timestamp)
        Timestamp.from_time(Time.at(timestamp))
      end

      trace_method(
        :_valid_message?,
        span_attribute_extractor: -> (processor, *_, **_) { processor.log_started_at(:valid_message?) },
        span_annotator: -> (processor, span, _, result) do
          processor.instrument(method: :valid_message?, aborted: !result, span:)
        end
      )

      trace_method :_feature_flag_skips_message?

      trace_method(
        :_max_associations_exceeded?,
        span_attribute_extractor: -> (processor, *_, **_) do
          processor.log_started_at(:max_associations_exceeded?)
        end,
        span_annotator: -> (processor, span, _, result) do
          processor.instrument(method: :max_associations_exceeded?, aborted: result, span:)
        end
      )

      trace_method(
        :_matching_elasticsearch_documents?,
        span_attribute_extractor: -> (processor, *_, **_) do
          processor.log_started_at(:matching_elasticsearch_documents?)
        end,
        span_annotator: -> (processor, span, _, result) do
          metric_only_tags = { "uses_any_match" => processor.any_match_helper_enabled?.to_s }
          processor.instrument(method: :matching_elasticsearch_documents?, aborted: !result, metric_only_tags:, span:)
        end
      )

      trace_method(
        :_canonical_data_present?,
        span_attribute_extractor: -> (processor, *_, **_) { processor.log_started_at(:canonical_data_present?) },
        span_annotator: -> (processor, span, _, result) do
          extra = {
            "dependent_mysql_replication_cluster" => processor.dependent_mysql_replication_cluster&.to_s
          }.compact
          processor.instrument(method: :canonical_data_present?, aborted: !result, extra:, span:)
        end
      )

      trace_method(
        :_update,
        span_attribute_extractor: -> (processor, *_, **_) { processor.log_started_at(:update) },
        span_annotator: -> (processor, span, _, _) { processor.instrument(method: :update, extra: processor.update_extra_tags, span:) }
      )

      trace_method(
        :consume,
        span_attribute_extractor: -> (processor, *_, **_) { processor.log_started_at(:consume) },
        span_annotator: -> (processor, span, _, result) do
          processor.instrument(method: :consume, aborted: (result.length == 1 && result.first.failed?), span:)
        end
      )

      # This method is conceptually private, but cannot actually be marked `private` due its use in the `trace_method`
      # configuration above.
      sig { params(method: Symbol).returns(T::Hash[T.untyped, T.untyped]) }
      def log_started_at(method)
        @started_at_by_method_name[method] = GitHub::Dogstats.monotonic_time

        # We only care about tracking the timestamp above, but since we must fulfill the contract of
        # `span_attribute_extractor`, we return an empty hash.
        #
        # We will actually add attributes the span later on.
        {}
      end

      # Instruments both a Datadog metric and a distributed trace for the given method.
      #
      # `extra` tags/attributes are added to BOTH the dogstats metric and the OTel span.
      # `metric_only_tags` are added ONLY to the dogstats metric — useful when you want
      # to slice charts on a dimension without inflating span attribute payloads (e.g.,
      # short-lived rollout-tracking tags).
      #
      # This method is conceptually private, but cannot actually be marked `private` due its use in the `trace_method`
      # configuration above.
      sig do
        params(
          span: OpenTelemetry::Trace::Span,
          method: Symbol,
          aborted: T::Boolean,
          extra: T::Hash[String, T.untyped],
          metric_only_tags: T::Hash[String, String],
        )
        .void
      end
      def instrument(span:, method:, aborted: false, extra: {}, metric_only_tags: {})
        if started_at = @started_at_by_method_name[method]
          GitHub.dogstats.distribution(
            METRIC_NAME_INDEX_TIME,
            GitHub::Dogstats.duration(started_at),
            tags: metric_tags(method:, aborted:, extra:, metric_only_tags:)
          )
        end

        # As per convention on span names, use the fully resolved method name, including the name of the processor
        # subclass e.g. "memex_project_column/indexable/processor/account_rename#consume"
        span.name = [self.class.name&.underscore, method].join("#")

        span.add_attributes(span_attributes(aborted:, extra:))
      end

      sig do
        params(
          method: Symbol,
          aborted: T::Boolean,
          extra: T::Hash[String, String],
          metric_only_tags: T::Hash[String, String],
        ).returns(T::Array[String])
      end
      private def metric_tags(method:, aborted:, extra: {}, metric_only_tags: {})
        [
          "action:#{method}",
          "processor:#{processor_subclass_name}",
          "index:#{index.name}",
          "aborted:#{aborted}",
        ]
          .concat(extra.map { |key, value| "#{key}:#{value}" })
          .concat(metric_only_tags.map { |key, value| "#{key}:#{value}" })
      end

      sig { params(aborted: T::Boolean, extra: T::Hash[String, String]).returns(T::Hash[String, T.untyped]) }
      private def span_attributes(aborted:, extra: {})
        {
          "processor" => processor_subclass_name,
          "index" => index.name,
          "aborted" => aborted,
        }.merge(extra)
      end

      # Subscribes to `instantiation.active_record` for the duration of the block, accumulating
      # per-model counts of ActiveRecord objects instantiated. Emits the block's wall-clock
      # duration as a distribution metric per tracked model, tagged with the association count
      # bucket. This lets us correlate "how many records were loaded" with "how long the job took".
      # Piggybacks on Rails' built-in instrumentation — no additional queries are issued.
      sig do
        type_parameters(:T)
          .params(models: T.nilable(T::Set[String]), blk: T.proc.returns(T.type_parameter(:T)))
          .returns(T.type_parameter(:T))
      end
      private def with_association_timings(models, &blk)
        return yield if models.blank?

        counts_by_model = T.let({}, T::Hash[String, Integer])
        callback = ->(_name, _start, _finish, _id, payload) {
          model = payload[:class_name]
          next unless models.include?(model)
          counts_by_model[model] = (counts_by_model[model] || 0) + payload[:record_count]
        }

        started_at = GitHub::Dogstats.monotonic_time
        result = ActiveSupport::Notifications.subscribed(callback, "instantiation.active_record") do
          yield
        end
        duration = GitHub::Dogstats.duration(started_at)

        counts_by_model.each do |model, count|
          GitHub.dogstats.distribution(
            METRIC_NAME_INDEX_DURATION_BY_ASSOCIATION_COUNT,
            duration,
            tags: [
              "processor:#{processor_subclass_name}",
              "index:#{index.name}",
              "cluster:#{index.cluster_name}",
              "model:#{model}",
              "bucket:#{MemexPerformanceStatsHelper.associations_height_bucket(count)}",
            ]
          )
        end

        result
      end

      # Returns the shortened name of the processor subclass e.g. "account_rename" rather than
      # "memex_project_column/indexable/processor/account_rename"
      sig { returns(String) }
      private def processor_subclass_name
        T.must(self.class.name).demodulize.underscore
      end

      # Whether we should enforce the max associations constraint. When `true`, messages
      # that exceed the constraint will be skipped.
      sig { returns(T::Boolean) }
      memoize private def max_associations_constraint_enabled?
        FeatureFlag.vexi.enabled?(:memex_max_associations_constraint, default: false)
      end
    end
  end
end
