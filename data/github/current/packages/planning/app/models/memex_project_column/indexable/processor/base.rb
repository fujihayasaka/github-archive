# typed: strict
# frozen_string_literal: true

module MemexProjectColumn::Indexable
  module Processor
    # This is the interface for classes that are responsible for copying data for a field supported in GitHub Projects
    # from its canonical source to the Elasticsearch cluster that we use to serve read requests. Subclasses of this
    # base class are attached to specific fields via the `Indexable#register_processors` method, which is typically
    # implemented by a subclass of `MemexProjectColumn::Field`.
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
      extend T::Sig
      extend T::Helpers
      include GitHub::Memoizer
      include GitHub::Tracing

      METRIC_NAME_INDEX_TIME = T.let("memex.indexable.processor.index_time", String)

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
      private :message

      sig { returns(Elastomer::Indexes::MemexProjectItems) }
      attr_reader :index
      private :index

      sig { returns(ElasticsearchClient) }
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

      sig { params(message: GitHub::StreamProcessors::Message).void }
      def initialize(message)
        @message = message
        @index = T.let(Elastomer::Indexes::MemexProjectItems.new, Elastomer::Indexes::MemexProjectItems)
        @es_client = T.let(ElasticsearchClient.new(@index), ElasticsearchClient)
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
        .params(es_client: ElasticsearchClient)
        .returns(T.any(ResyncProjectsResult, ElasticsearchClient::Response, T::Array[ElasticsearchClient::Response]))
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
      sig { overridable.returns(T::Array[ObjectWithGlobalRelayId]) }
      def updated_models; []; end

      sig { returns(T::Array[ProcessedResult]) }
      def consume
        return failure(FailureReason::MESSAGE_IGNORED) unless _valid_message?
        return failure(FailureReason::NO_MATCHING_DOCS) unless _matching_elasticsearch_documents?
        return failure(FailureReason::CONTENT_MISSING) unless _canonical_data_present?

        _update
      end

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

      # This wrapper is necessary for the `trace_method` macro. Without it, each subclass would have to do its own
      # instrumentation for the overidden `matching_elasticsearch_documents?` method.
      sig { returns(T::Boolean) }
      private def _matching_elasticsearch_documents?
        matching_elasticsearch_documents?
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
              elasticsearch_update_response: response,
              updated_memex_ids: project_ids_to_resync_on_failure,
              updated_models: updated_models
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

      trace_method(
        :_matching_elasticsearch_documents?,
        span_attribute_extractor: -> (processor, *_, **_) do
          processor.log_started_at(:matching_elasticsearch_documents?)
        end,
        span_annotator: -> (processor, span, _, result) do
          processor.instrument(method: :matching_elasticsearch_documents?, aborted: !result, span:)
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
        span_annotator: -> (processor, span, _, _) { processor.instrument(method: :update, span:) }
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
      # This method is conceptually private, but cannot actually be marked `private` due its use in the `trace_method`
      # configuration above.
      sig do
        params(
          span: OpenTelemetry::Trace::Span,
          method: Symbol,
          aborted: T::Boolean,
          extra: T::Hash[String, T.untyped]
        )
        .void
      end
      def instrument(span:, method:, aborted: false, extra: {})
        if started_at = @started_at_by_method_name[method]
          GitHub.dogstats.distribution(
            METRIC_NAME_INDEX_TIME,
            GitHub::Dogstats.duration(started_at),
            tags: metric_tags(method:, aborted:, extra:)
          )
        end

        # As per convention on span names, use the fully resolved method name, including the name of the processor
        # subclass e.g. "memex_project_column/indexable/processor/account_rename#consume"
        span.name = [self.class.name&.underscore, method].join("#")

        span.add_attributes(span_attributes(aborted:, extra:))
      end

      sig { params(method: Symbol, aborted: T::Boolean, extra: T::Hash[String, String]).returns(T::Array[String]) }
      private def metric_tags(method:, aborted:, extra: {})
        [
          "action:#{method}",
          "processor:#{processor_subclass_name}",
          "aborted:#{aborted}"
        ].concat(extra.map { |key, value| "#{key}:#{value}" })
      end

      sig { params(aborted: T::Boolean, extra: T::Hash[String, String]).returns(T::Hash[String, T.untyped]) }
      private def span_attributes(aborted:, extra: {})
        {
          "processor" => processor_subclass_name,
          "aborted" => aborted
        }.merge(extra)
      end

      # Returns the shortened name of the processor subclass e.g. "account_rename" rather than
      # "memex_project_column/indexable/processor/account_rename"
      sig { returns(String) }
      private def processor_subclass_name
        T.must(self.class.name).demodulize.underscore
      end
    end
  end
end
