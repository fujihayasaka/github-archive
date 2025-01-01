# typed: strict
# frozen_string_literal: true

require "hashdiff"

module Search
  # This class is used to keep the Elasticsearch (ES) index for project items in sync with the latest data from
  # canonical sources. Those canonical sources are typically non-Projects-owned MySQL clusters, but they also include
  # resources that can only be fetched over HTTP APIs.
  #
  # In our production environment, this class is only intended for use from the `ResyncMemexProjectItemsIndexJob`,
  # which implements a batched resync of an entire project as our last resort resilience mechanism (usually because
  # our more granular event processing approach has failed).
  #
  # In development and test, this class may be used as an easy way to resync a project.
  #
  # This class requires instantiation with a single project ID, which we use to restrict the potentially destructive
  # behaviour of this class to a single project. With an instance of this class, callers can use one of two public
  # methods to perform the resync:
  #
  #   1. `reconcile!`, which adds, updates, or remove ES documents for a given batch of project items. This method
  #      emits logs/metrics describing its own behaviour (please see the method comment on `reconcile!`).
  #   2. `clear!`, which removes all ES documents whose ID is greater than or equal to a given item ID. This method
  #      does not emit any logs.
  #
  # EXAMPLE:
  #
  #   # Instantiate a reconciler that is tied to a particular project.
  #   reconciler = Search::MemexProjectItemReconciler.new(memex_project.id)
  #
  #   # Reconcile all items in the project in batches.
  #   memex_project.memex_project_items.in_batches do |batch|
  #     reconciler.reconcile!(batch)
  #   end
  #
  #   # Remove any items from Elasticsearch that are no longer in MySQL.
  #   reconciler.clear!(greater_than_or_equal_to_item_id: memex_project.memex_project_items.last.id)
  class MemexProjectItemReconciler
    include GitHub::Tracing
    include GitHub::Memoizer

    DEFAULT_PAGE_SIZE = 1000
    LOG_MESSAGE = "Reconciling project item data with Elasticsearch"
    METRIC_NAME = "memex.project_item_reconciler.reconcile"

    # Known fields that are highly variable and inconsistent. If a document that is being updated only includes fields
    # listed it will be ignored when calculating the consistency score. It is highly discouraged to add fields to this
    # list unless they are truly inconsistent and can't be relied upon towards the final consistency score.
    INCONSISTENT_FIELDS = T.let(%w[updated_at], T::Array[String])

    # Represents the result of a `reconcile!` or `clear!` operation.
    class Result
      # The number of items that were added to Elasticsearch during the operation.
      sig { returns(Integer) }
      attr_reader :added

      # The number of items that were updated in Elasticsearch during the operation.
      sig { returns(Integer) }
      attr_reader :updated

      # The number of items that were removed from Elasticsearch during the operation.
      sig { returns(Integer) }
      attr_reader :removed

      # The number of items that were unable to be processed because a document could not be built from the DB.
      sig { returns(Integer) }
      attr_reader :incomplete

      # The number of Elasticsearch errors encountered during the operation.
      sig { returns(Integer) }
      attr_reader :errored

      sig do
        params(
          documents_to_add: T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root],
          documents_to_update: T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root],
          document_ids_to_remove: T::Set[String],
          incomplete_document_ids: T::Set[String],
          inconsistent_document_ids_to_ignore: T::Set[String],
          response: T::Hash[T.untyped, T.untyped],
          force_removed: T.nilable(Integer),
        )
        .void
      end
      def initialize(documents_to_add: [], documents_to_update: [], document_ids_to_remove: Set.new, incomplete_document_ids: Set.new, inconsistent_document_ids_to_ignore: Set.new, response: {}, force_removed: nil)
        failed_document_ids = if response["errors"]
          Set.new(
            response["items"]
              .select { |operation| operation.values.first["error"].present? }
              .map { |operation| operation.values.first["_id"] }
          )
        else
          Set.new
        end

        @added = T.let((Set.new(documents_to_add.map(&:_id)) - failed_document_ids).size, Integer)
        @updated = T.let((Set.new(documents_to_update.map(&:_id)) - inconsistent_document_ids_to_ignore - failed_document_ids).size, Integer)
        @removed = T.let(force_removed || (document_ids_to_remove - failed_document_ids).size, Integer)
        @incomplete = T.let(incomplete_document_ids.size, Integer)
        @errored = T.let(failed_document_ids.to_a.length, Integer)
      end

      # The total number of items that were added, updated, or removed during the operation.
      sig { returns(Integer) }
      def total
        added + updated + removed
      end
    end

    # Internal representation of a document that we've found in Elasticsearch.
    class Document
      sig { returns(String) }
      attr_reader :id

      sig { returns(String) }
      attr_reader :routing

      sig { returns(T::Hash[String, T.untyped]) }
      attr_reader :source

      sig { params(document: T::Hash[String, T.untyped]).void }
      def initialize(document)
        @id = T.let(document["_id"], String)
        @routing = T.let(document["_routing"], String)
        @source = T.let(document["_source"], T::Hash[String, T.untyped])
      end
    end

    # We report this errors to Failbot when any of the Elasticsearch bulk APIs returns an error.
    class BulkRequestError < StandardError; end

    # Instantiates a reconciler that is tied to a specific project (so that we restrict the potentially destructive
    # behaviour of the reconciler to a single project).
    #
    # @param memex_project_id - ID of the project this reconciler is to be associated with.
    # @param read_only - Whether or not this reconciler should be read-only (for example when calculating a consistency
    # score)
    # @param live_updates - Whether or not this reconciler should broadcast live updates to the frontend after a
    # successful reconciliation.
    # @param index - The index to reconcile against. If nil, the primary index will be used.
    sig { params(memex_project_id: Integer, read_only: T.nilable(T::Boolean), live_updates: T.nilable(T::Boolean), index: T.nilable(Elastomer::Indexes::MemexProjectItems)).void }
    def initialize(memex_project_id, read_only: false, live_updates: true, index: nil)
      @memex_project_id = memex_project_id
      @index = T.let(index || Elastomer::Indexes::MemexProjectItems.new, Elastomer::Indexes::MemexProjectItems)
      @diff_by_document_id = T.let({}, T::Hash[String, T::Array[T.untyped]])
      @inconsistent_document_ids_to_ignore = T.let(Set.new, T::Set[String])

      @read_only = T.let(read_only || false, T::Boolean)
      @live_updates = T.let(live_updates || false, T::Boolean)

      # These are all declared as nil, but are set to non-nil values when necessary in `prepare_reconciliation!`
      @memex_project_item_by_id = T.let(nil, T.nilable(T::Hash[String, MemexProjectItem]))
      @elasticsearch_document_by_id = T.let(nil, T.nilable(T::Hash[String, Document]))
      @document_ids_to_remove = T.let(nil, T.nilable(T::Set[String]))
      @documents_to_add = T.let(nil, T.nilable(T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root]))
      @documents_to_update = T.let(nil, T.nilable(T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root]))
      @incomplete_document_ids = T.let(Set.new, T::Set[String])
    end

    # Reconciles the canonical item data for a given batch of items with the data in Elasticsearch.
    #
    # The reconciliation process consists of three steps:
    #
    #   1. For any item that is in the given batch but not in Elasticsearch, we add a new document to Elasticsearch.
    #   2. For any item that is both in the given batch and in Elasticsearch, we update the Elasticsearch document
    #      with the latest content if necessary.
    #   3. For any remaining Elasticsearch document whose ID is within the inclusive range batch.min(:id) and
    #      batch.max(:id), we remove the document since it no longer exists in MySQL.
    #
    # This method reports on its own behaviour by emitting two types of logs:
    #
    #   i.  A Datadog metric, named `Search::MemexProjectItemReconciler::METRIC_NAME`, which is tagged with an
    #       appropriate action for each addition, update, or deletion e.g. `action:add`.
    #   ii. A INFO-level log statement (which ends up in Splunk), with the message
    #       `Search::MemexProjectItemReconciler::LOG_MESSAGE`, and which is also tagged with an action e.g.
    #       `gh.memex.project_item_reconciler.action=add`. For update actions, the log message also contains the diff
    #       that triggered the update under the `gh.memex.project_item_reconciler.diff` key. The value of that key is
    #       in the format generated by the HashDiff gem (see https://github.com/liufengyun/hashdiff#diff).
    #
    # @param memex_project_items - Batch of items to reconcile. These must be sorted in ascending order by ID.
    # @param wait_for_refresh - Whether or not we should wait for the updated data to be searchable in Elasticsearch
    #   before returning. This defaults to nil/false, because the data will typically becomes searchable within one
    #   second of the write (see https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html)
    sig do
      params(memex_project_items: T::Array[MemexProjectItem], wait_for_refresh: T.nilable(T::Boolean), timestamp: T.nilable(Integer))
      .returns(Result)
    end
    def reconcile!(memex_project_items, wait_for_refresh: false, timestamp: Time.now.to_i)
      proceed_with_reconciliation = prepare_reconciliation!(memex_project_items)
      return Result.new unless proceed_with_reconciliation

      @documents_to_add = T.must(@documents_to_add)
      @documents_to_update = T.must(@documents_to_update)
      @document_ids_to_remove = T.must(@document_ids_to_remove)
      @elasticsearch_document_by_id = T.must(@elasticsearch_document_by_id)
      return Result.new if [@documents_to_add, @documents_to_update, @document_ids_to_remove].all?(&:empty?)

      response = @index.bulk({ refresh: wait_for_refresh ? "wait_for" : nil }.compact) do |request|
        request = T.cast(request, ElastomerClient::Client::Bulk)

        @documents_to_add.each do |document|
          doc = document.to_hash
          params = Elastomer::Index.separate_document_and_params(doc, cluster_running_version_8_plus: @index.client.version_support.es_version_8_plus?)
          request.index(doc, params.merge({ routing: document._routing })) unless read_only?
          log_add(doc[:database_id].to_s)
        end

        @documents_to_update.each do |document|
          doc = document.to_hash
          params = Elastomer::Index.separate_document_and_params(doc, cluster_running_version_8_plus: @index.client.version_support.es_version_8_plus?)
          request.index(doc, params.merge({ routing: document._routing })) unless read_only?
          log_update(doc[:database_id].to_s)
        end

        @document_ids_to_remove.each do |id|
          document = @elasticsearch_document_by_id[id]

          # ES8-COMPATIBILITY: Omit `type` from the parameters passed to the bulk delete API when targeting ES 8
          # (where `type` is no longer supported).
          document_type = unless @index.index_running_version_8_plus?
            Elastomer::Adapters::MemexProjectItem.document_type
          end

          if document
            params = Elastomer::Index.separate_document_and_params({ _id: document.id, _routing: document.routing, _type: document_type }, cluster_running_version_8_plus: @index.client.version_support.es_version_8_plus?)
            request.delete(params) unless read_only?
            log_delete(document.id)
          end
        end
      end

      # When this class is in read-only mode, the response object comes back as nil. Rather than nil check everywhere this ensures we get back a hash.
      response ||= {}

      if response["errors"].present?
        errors = response["items"].select { |operation| operation.values.first["error"].present? }
        log_bulk_errors("reconcile!", "Bulk index error", errors)
      end

      if live_updates? && response["errors"].blank?
        MemexProjectColumn::Interface::Indexable::Processor::LiveUpdateBroadcaster.call(
          memex_project_ids: [@memex_project_id],
          timestamp: T.must(timestamp)
        )
      end

      Result.new(
        documents_to_add: @documents_to_add,
        documents_to_update: @documents_to_update,
        document_ids_to_remove: @document_ids_to_remove,
        incomplete_document_ids: @incomplete_document_ids,
        inconsistent_document_ids_to_ignore: @inconsistent_document_ids_to_ignore,
        response: response
      )
    ensure
      log_incomplete(@incomplete_document_ids)
    end

    # Removes stale documents from Elasticsearch.
    #
    # It is the caller's responsibility to ensure that this method only targets items that no longer exist in MySQL.
    #
    # This method does not report any logs or metrics.
    #
    # @param greater_than_or_equal_to_item_id - The ID of the first item to remove from Elasticsearch. All items with
    #   an ID greater than or equal to this value will be removed. If nil, all items in the project this reconciler
    #   was initialized with will be removed.
    # @param wait_for_refresh - Whether or not we should wait for the deleted data to be truly removed from
    #   Elasticsearch before returning. This defaults to false, because the deletions will typically be reflected
    #   within one second of the write (see https://www.elastic.co/guide/en/elasticsearch/reference/current/docs-refresh.html)
    sig do
      params(greater_than_or_equal_to_item_id: T.nilable(Integer), wait_for_refresh: T.nilable(T::Boolean))
      .returns(Result)
    end
    def clear!(greater_than_or_equal_to_item_id: nil, wait_for_refresh: false)
      response = @index.client.delete_by_query(
        item_query(greater_than_or_equal_to_item_id: greater_than_or_equal_to_item_id),
        {
          type: Elastomer::Adapters::MemexProjectItem.document_type,
          routing: @memex_project_id.to_s,
          index: @index.name,
          refresh: wait_for_refresh ? "true" : nil,
        }.compact
      )

      if response["failures"].present?
        log_bulk_errors("clear!", "Delete by query error", response["failures"])
      end

      Result.new(
        force_removed: response["deleted"].to_i,
        response:,
      )
    end

    sig { params(document_id: String, diff: T::Array[T.untyped]).void }
    private def store_document_diff(document_id, diff)
      @diff_by_document_id[document_id] = diff
      return unless consistency_score_ignores_inconsistent_fields?

      fields_changed = diff.collect { |(_, field, _, _)| field }
      inconsistent_fields_changed = fields_changed.all? { INCONSISTENT_FIELDS.include?(_1) }
      @inconsistent_document_ids_to_ignore << document_id if inconsistent_fields_changed
    end

    sig { returns(T.nilable(MemexProject)) }
    memoize private def memex_project
      MemexProject.includes(:memex_project_columns).find_by(id: @memex_project_id)
    end

    sig { returns(T::Boolean) }
    memoize private def consistency_score_ignores_inconsistent_fields?
      memex_project&.owner&.feature_enabled?(:memex_project_consistency_score_ignore_inconsistent_fields) || false
    end

    sig { params(memex_project_items: T::Array[MemexProjectItem]).returns(T::Boolean) }
    private def prepare_reconciliation!(memex_project_items)
      unless memex_project_items.all? { |i| i.memex_project_id == @memex_project_id }
        raise ArgumentError.new("All items must belong to the project this reconciler was initialized with.")
      end

      unless memex_project_items.each_cons(2).all? { |a, b| T.must(a&.id) <= T.must(b&.id) }
        raise ArgumentError.new("Items must be ordered by increasing id.")
      end

      return false if memex_project_items.empty?
      return false unless project = memex_project

      preload_data(project, memex_project_items)

      @memex_project_item_by_id = memex_project_items.index_by { |i| i.id.to_s }

      elasticsearch_documents = fetch_elasticsearch_documents(memex_project_items)
      @elasticsearch_document_by_id = elasticsearch_documents.index_by(&:id)

      database_ids = memex_project_items.map { |i| i.id.to_s }.compact.to_set
      elasticsearch_ids = elasticsearch_documents.map(&:id).to_set

      @documents_to_add = (database_ids - elasticsearch_ids).each_with_object([]) do |id, result|
        doc = build_document(@memex_project_item_by_id[id])
        doc.present? ? result << doc : @incomplete_document_ids.add(id)
      end
      @documents_to_update = compute_document_diffs(database_ids & elasticsearch_ids).compact
      @document_ids_to_remove = elasticsearch_ids - database_ids

      true
    end

    sig { params(memex_project_items: T::Array[MemexProjectItem]).returns(T::Array[Document]) }
    private def fetch_elasticsearch_documents(memex_project_items)
      documents = T.let([], T::Array[Document])
      has_more_documents = T.let(true, T::Boolean)
      search_after = T.let(nil, T.nilable(T::Array[Integer]))

      while has_more_documents
        query = item_query(
          greater_than_or_equal_to_item_id: T.must(memex_project_items.first).id,
          less_than_or_equal_to_item_id: T.must(memex_project_items.last).id
        ).merge({ search_after: search_after }.compact)

        hits = @index.search(query, routing: @memex_project_id, size: DEFAULT_PAGE_SIZE).dig("hits", "hits")

        documents += hits.map { |doc| Document.new(doc) }
        has_more_documents = hits.any?
        search_after = hits.last&.fetch("sort", nil)
      end

      documents
    end

    sig do
      params(document_ids: T::Set[String])
      .returns(T::Array[Elastomer::Interfaces::Document::MemexProjectItem::Root])
    end
    private def compute_document_diffs(document_ids)
      @elasticsearch_document_by_id = T.must(@elasticsearch_document_by_id)
      @memex_project_item_by_id = T.must(@memex_project_item_by_id)

      document_ids.each_with_object([]) do |id, result|

        # If the document returns nil, it means the document is in a transitional or error state and can't be indexed.
        # Add it to an array of incomplete documents to process later.
        unless latest_document = build_document(@memex_project_item_by_id.fetch(id))
          @incomplete_document_ids.add(id)
          next
        end

        previously_indexed_document = @elasticsearch_document_by_id.fetch(id).source

        # Remove metadata fields (those that begin with an underscore) from both documents; they are intentionally not
        # considered for the diff.
        previously_indexed_document = previously_indexed_document.select { |key, _| !key.start_with?("_") }
        comparable_latest_document = latest_document.to_hash.select { |key, _| !key.start_with?("_") }

        # Sort the field_values arrays of each document in place so that the diff is not affected by ordering (which
        # is arbitrary).
        previously_indexed_document["field_values"].sort_by! { |f| f["field_id"] }
        comparable_latest_document[:field_values].sort_by! { |f| f[:field_id] }

        diff = Hashdiff.diff(
          previously_indexed_document,
          comparable_latest_document,
          indifferent: true,

          # This option ensures that we avoid an algorithm that is known to perform poorly on hashes larger than 10kb
          # (see https://github.com/liufengyun/hashdiff/issues/49). Our hashes are only expected to be 2kb on average,
          # but we disable LCS anyway as a precaution. The only consequence of this is that array diffs are a bit
          # harder to interpret.
          use_lcs: false
        )

        if diff.any?
          store_document_diff(id, diff)
          result << latest_document
        end
      end
    end

    sig do
      params(
        greater_than_or_equal_to_item_id: T.nilable(Integer),
        less_than_or_equal_to_item_id: T.nilable(Integer)
      )
      .returns(T::Hash[T.untyped, T.untyped])
    end
    private def item_query(greater_than_or_equal_to_item_id: nil, less_than_or_equal_to_item_id: nil)
      query = {
        query: {
          bool: {
            filter: {
              term: {
                memex_project_id: {
                  value: @memex_project_id
                }
              }
            }
          }
        },
        sort: [
          {
            database_id: :asc
          }
        ]
      }

      if greater_than_or_equal_to_item_id || less_than_or_equal_to_item_id
        # Add an additional query clause to restrict the range of item IDs.
        query[:query][:bool].merge!(
          {
            must: {
              range: {
                database_id: {
                  gte: greater_than_or_equal_to_item_id,
                  lte: less_than_or_equal_to_item_id,
                }.compact
              }
            }
          }
        )
      end

      query
    end

    sig { params(memex_project: MemexProject, memex_project_items: T::Array[MemexProjectItem]).void }
    private def preload_data(memex_project, memex_project_items)
      GitHub::PrefillAssociations.prefill_associations(
        memex_project_items,
        :memex_project,
        available_records: [memex_project]
      )

      memex_project.memex_project_columns.each do |column|
        field = column.to_field
        next unless field.present?
        next if field.class.exclude_from_index?

        field.preload_elasticsearch_document_data(memex_project_items)
      rescue MemexProjectColumn::FieldDependency::MissingFieldImplementation
      end
    end

    sig do
      params(item: MemexProjectItem)
      .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Root))
    end
    def build_document(item)
      log_errors(item) do
        Elastomer::Adapters::MemexProjectItem.create(item).document
      end
    end

    sig do
      params(
        item: MemexProjectItem,
        blk: T.proc.returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Root)),
      )
      .returns(T.nilable(Elastomer::Interfaces::Document::MemexProjectItem::Root))
    end
    def log_errors(item, &blk)
      begin
        yield
      rescue => exception # rubocop:todo Lint/GenericRescue
        critical = !exception.is_a?(Elastomer::Adapters::MemexProjectItem::CanonicalDataMissingError)
        GitHub.dogstats.increment(
          "#{METRIC_NAME}.skip",
          tags: ["critical:#{critical}", "read_only:#{read_only?}", "exception:#{exception.class.name}"]
        )
        GitHub.logger.info(
          "Failed to build document for MemexProjectItem #{item.id}. Skipping.",
          shared_log_attributes(item.id.to_s).merge({
            "gh.memex.project_item_reconciler.action" => "build_document",
            "gh.memex.project_item_reconciler.read_only" => read_only?,
            "exception.class" => exception.class.name,
            "exception.message" => exception.message,
            "exception.stacktrace" => exception.backtrace&.join("\n"),
            "gh.memex.project_item_reconciler.critical_error" => critical,
          })
        )
        nil
      end
    end

    sig { params(document_id: String).void }
    def log_add(document_id)
      GitHub.logger.info(
        LOG_MESSAGE,
        shared_log_attributes(document_id).merge({
          "gh.memex.project_item_reconciler.action" => "add",
          "gh.memex.project_item_reconciler.read_only" => read_only?,
          "gh.memex.project_item_reconciler.counted" => true,
        })
      )
      GitHub.dogstats.increment(METRIC_NAME, tags: ["action:add", "read_only:#{read_only?}"])
    end

    sig { params(document_id: String).void }
    def log_update(document_id)
      GitHub.logger.info(
        LOG_MESSAGE,
        shared_log_attributes(document_id).merge({
          "gh.memex.project_item_reconciler.action" => "update",
          "gh.memex.project_item_reconciler.diff" => @diff_by_document_id[document_id],
          "gh.memex.project_item_reconciler.read_only" => read_only?,
          "gh.memex.project_item_reconciler.counted" => !@inconsistent_document_ids_to_ignore.include?(document_id),
        })
      )
      GitHub.dogstats.increment(METRIC_NAME, tags: ["action:update", "read_only:#{read_only?}"])
    end

    sig { params(document_id: String).void }
    def log_delete(document_id)
      GitHub.logger.info(
        LOG_MESSAGE,
        shared_log_attributes(document_id).merge({
          "gh.memex.project_item_reconciler.action" => "delete",
          "gh.memex.project_item_reconciler.batch" => @document_ids_to_remove.to_a,
          "gh.memex.project_item_reconciler.read_only" => read_only?,
          "gh.memex.project_item_reconciler.counted" => true,
        })
      )
      GitHub.dogstats.increment(METRIC_NAME, tags: ["action:delete", "read_only:#{read_only?}"])
    end

    sig { params(document_ids: T::Set[String]).void }
    def log_incomplete(document_ids)
      document_ids.each do |document_id|
        GitHub.logger.info(
          "Failed to build document for MemexProjectItem #{document_id}. Skipping.",
          shared_log_attributes(document_id).merge({
            "gh.memex.project_item_reconciler.action" => "incomplete",
            "gh.memex.project_item_reconciler.read_only" => read_only?
          })
        )
      end

      # Count the number of incomplete documents in Datadog.
      GitHub.dogstats.count("memex.project_item_reconciler.incomplete", document_ids.length)
    end

    sig { params(function: String, message: String, errors: T::Array[T.untyped]).void }
    def log_bulk_errors(function, message, errors)
      # Log the full error message to Splunk.
      GitHub.logger.info(
        message,
        shared_log_attributes.merge({
          "code.function" => function,
          "gh.memex.project_item_reconciler.error" => errors.to_json
        })
      )

      # Log an abbreviated error message to Sentry.
      Failbot.report(BulkRequestError.new(errors.take(3).to_json))

      # Count the number of bulk errors in Datadog.
      GitHub.dogstats.count(
        "memex.project_item_reconciler.bulk_errors",
        errors.length,
        tags: ["function:#{function.gsub(/[^\w]/, '')}"]
      )
    end

    sig { params(document_id: T.nilable(String)).returns(T::Hash[T.untyped, T.untyped]) }
    def shared_log_attributes(document_id = nil)
      {
        "code.namespace" => self.class.name,
        "code.function" => "reconcile!",
        "elasticsearch.index" => @index.name,
        "elasticsearch.document.id" => document_id,
        "gh.memex.project.id" => @memex_project_id,
      }.compact
    end

    sig { returns(T::Boolean) }
    private def read_only? = @read_only

    sig { returns(T::Boolean) }
    private def live_updates? = @live_updates

    # Each call to `trace_method` here must appear after the definition of the method it instruments
    # in order to workaround a limitation in Sorbet.
    #
    # See https://github.com/sorbet/sorbet/issues/5025#issuecomment-1228146684.
    trace_method :reconcile!
    trace_method :clear!
    trace_method :prepare_reconciliation!
    trace_method :fetch_elasticsearch_documents
    trace_method :compute_document_diffs
    trace_method :preload_data
  end
end
