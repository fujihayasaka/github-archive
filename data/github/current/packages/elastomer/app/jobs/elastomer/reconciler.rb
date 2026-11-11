# typed: true
# frozen_string_literal: true

require "timeout"

module Elastomer
  # The task of Reconciler is to iterate over ActiveRecord models and ensure
  # that their representations in the search index are up to date. Documents
  # will be added and removed from the search index; others will be updated.
  # Whatever it takes to make the search index look like the database.
  #
  # The up-to-dateness of a search document is determined by comparing
  # fields from the document with the corresponding fields from
  # the ActiveRecord model. By default this is the `updated_at` field, but
  # any number of fields can be specified.
  #
  # The Reconciler uses a shared mutex to maintain state. Multiple threads
  # and processes can work on reconciling - even processes on separate
  # machines.

  class Reconciler
    include GitHub::Memoizer
    include Elastomer::RedisMutexDependency
    MAX_ELASTICSEARCH_DOCUMENTS_PER_REQUEST = 2000
    DEFAULT_LIMIT = 100
    LAST_ID_CACHE_TTL = 5.minutes
    LAST_ID_ERROR_CACHE_TTL = 1.day

    # Raised when a custom query provided via `named_elasticsearch_queries` is invalid.
    class InvalidNamedElasticsearchQueryError < StandardError; end

    #### Required (these must be supplied via the initializer)

    # The Elastomer::Index instance being reconciled against the DB.
    attr_reader :index

    # The type of data being reconciled. The AR model class is derived from
    # this value. It should be the document type as found in the :index.
    attr_reader :type

    # The Redis hash key where settings for this reconciler will be stored.
    attr_reader :group_key

    #### Defaults Provided

    # ElasticSearch document type (if different from the AR type)
    attr_reader :es_type

    # The array of fields used to determine if a search record
    # needs to be updated (defaults to %w[updated_at]).
    attr_reader :fields

    # The number of AR models to retrieve per iteration (default is 100).
    attr_reader :limit

    # The Redis connection to use (default is GitHub.legacy_redis).
    attr_reader :redis

    # The parent job that initiated this reconciler (if any).
    attr_reader :parent_job

    private :redis

    # ElasticSearch bulk request size in bytes (default is 500kb).
    attr_reader :request_size

    # Extra SQL conditions for restricting the selected AR models. Can pass a
    # String directly or use a Proc to build the string. The Proc is called
    # with one argument, the current reconciler.
    attr_reader :conditions

    # Extra SQL joins for restricting the selected AR models.
    attr_reader :joins

    # Eager load these models
    attr_reader :ar_includes

    # Prefill these batch methods into the models
    attr_reader :prefills

    # AR models will not be indexed if any of these methods return true.
    # Array of method symbols.
    attr_reader :reject

    # AR models will only be indexed if all of these methods return true.
    # Array of method symbols.
    attr_reader :accept

    # Adapter args to pass to the adapter instantiation
    attr_reader :adapter_args

    #### Derived from the type

    # The AR model class to reconcile against.
    attr_reader :model_class

    # Can pass a Proc to build custom ActiveRecord query before fetching rows.
    attr_reader :model_scope

    sig { returns(T::Hash[Symbol, T.proc.params(id: Integer).returns(T.untyped)]) }
    attr_reader :named_scopes

    sig { returns(T::Hash[Symbol, T.proc.params(id: Integer, document_id_range: T::Range[Integer]).returns(T.untyped)]) }
    attr_reader :named_elasticsearch_queries

    # Various redis keys
    attr_reader :offset_key
    attr_reader :total_key
    attr_reader :add_key
    attr_reader :update_key
    attr_reader :remove_key
    attr_reader :error_key
    attr_reader :finished_key
    attr_reader :last_id_key
    attr_reader :last_id_cache_expires_key

    class MaximumIdQueryFailedError < StandardError; end

    # Raise errors for debuggability in dev and test
    attr_reader :raise_errors

    # The extra parameters to pass to the :conditions block
    attr_reader :proc_args

    # Raised when a bulk index operation fails and the job caller has initialized with `raise_errors: true`
    class BulkIndexResponseError < StandardError
    end

    # Create a new Reconciler that will reconcile the state of a single
    # AR model type in the database with the documents in the search index.
    # Specific fields will be compared to determine if the two
    # representations are out of sync.
    #
    # The database will not be changed by this process. Only the search
    # index will be updated.
    #
    # The reconcile progress is tracked via several Redis keys. Multiple
    # reconcilers can be run simultaneously, and they will coordinate work
    # via the Redis keys and a shared mutex.
    #
    # opts - Options Hash
    #        :index        - Elastomer::Index to reconcile
    #        :type         - AR document type to reconcile
    #        :model_scope  - Customize AR scope using a Proc (optional)
    #        :es_type      - ES document type (default to `:type`)
    #        :group_key    - redis hash key
    #        :fields       - fields to check for reconciliation
    #        :force_reindex - Reindex every record, no matter if their :fields have changed
    #        :delete_documents_from_es - Remove documents from the index that are not in the database
    #        :limit        - number of AR models to fetch
    #        :redis        - the redis connection to use
    #        :request_size - ElasticSearch bulk request size in bytes
    #        :conditions   - extra SQL conditions on the AR model
    #        :joins        - extra SQL joins to use on the AR model
    #        :include      - eager load these AR model associations (Array of symbols)
    #        :accept       - AR model methods that must be true (Array of symbols)
    #        :reject       - AR model methods that must be false (Array of symbols)
    #        :raise_errors - Raise errors for debuggability in dev and test (default: false)
    #        :named_scopes - A Hash of named scopes to be used as the 'canonical_scope' (symbol keys and Proc values)
    #                        The Proc will be called with an id and should return an ActiveRecord::Relation for the model_class.
    #        :named_elasticsearch_queries - A Hash of named Elasticsearch queries to be used when querying ES (symbol keys and Proc values).
    #                        The Proc will be called with an id and a document_id_range, and should return a complete Elasticsearch query structure (not just filters).
    #        :proc_args    - The extra parameters to pass to the :conditions proc
    #
    def initialize(opts)
      @index = opts.fetch(:index)
      @type = opts.fetch(:type)
      @group_key = opts.fetch(:group_key)
      @model_class = opts[:model_class]
      @models = nil
      if @model_class.nil?
        @model_class = type.tr("-", "_").classify.constantize
      end
      @model_scope = opts[:model_scope]
      @es_type = opts.fetch(:es_type, @type)

      @fields = opts.fetch(:fields, %w[updated_at])
      @delete_documents_from_es = opts.fetch(:delete_documents_from_es, true)
      @force_reindex = opts.fetch(:force_reindex, !@delete_documents_from_es)
      @limit = opts.fetch(:limit, DEFAULT_LIMIT)
      @redis = opts.fetch(:redis, GitHub.legacy_redis)
      @request_size = opts.fetch(:request_size, 512.kilobytes)
      @conditions = opts.fetch(:conditions, nil)
      @joins = opts.fetch(:joins, nil)
      @ar_includes  = opts.fetch(:include, nil)
      @prefills     = opts.fetch(:prefills, [])
      @raise_errors = opts.fetch(:raise_errors, false)
      @proc_args    = opts.fetch(:proc_args, nil)
      # We expect seconds as an input; convert to milliseconds for use in .limit_execution_time
      # Must be passed as at least 1s
      @query_timeout = opts.fetch(:query_timeout, 5).to_i * 1000
      @named_scopes = opts.fetch(:named_scopes, {})
      @named_elasticsearch_queries = opts.fetch(:named_elasticsearch_queries, {})
      @parent_job = T.let(
        proc_args&.first.is_a?(Elastomer::RepairJob) ? proc_args.first : nil,
        T.nilable(Elastomer::RepairJob)
      )

      @accept       = Array(opts[:accept])
      @reject       = Array(opts[:reject])

      @adapter_args = opts[:adapter_args] || {}

      @offset_key   = "#@group_key/offset"
      @total_key    = "#@group_key/total"
      @add_key      = "#@group_key/add"
      @update_key   = "#@group_key/update"
      @remove_key   = "#@group_key/remove"
      @error_key    = "#@group_key/error"
      @finished_key = "#@group_key/finished"
      @last_id_key = "#@group_key/last_id"
      @last_id_cache_expires_key = "#@group_key/last_id_cache_expires"
    end

    # Returns the array of stats keys.
    def keys
      [total_key, add_key, update_key, remove_key, error_key, finished_key]
    end

    # Reset the reconciler by clearing all redis keys and removing the
    # mutex.
    #
    # Returns this reconciler.
    def reset!
      redis.pipelined do |pipeline|
        pipeline.hdel(group_key, offset_key, last_id_key, last_id_cache_expires_key, *keys)
      end
      @all_memoized&.delete(:offset)
      @all_memoized&.delete(:cached_last_id)
      mutex.unlock!
      @models = nil
      self
    end

    # Returns `true` if there are no more models to operate on. Returns
    # `false` if there are more models.
    def finished?
      redis.hexists(group_key, finished_key)
    end

    # Internal: Set the finished timestamp in redis to the current time.
    def finish!
      redis.hsetnx(group_key, finished_key, Time.now.iso8601)
    end

    def progress
      value = bypass_mysql_for_progress_calculation? ? cached_last_id : last_id
      return 0.0 if value.nil?
      return 0.0 unless value > 0
      (offset.to_f / value.to_f) * 100.0
    end

    def bypass_mysql_for_progress_calculation?
      if parent_job.present?
        FeatureFlag.vexi.enabled?(:elastomer_reconciler_bypass_mysql_for_progress_calculation, parent_job.class.name, default: true)
      else
        FeatureFlag.vexi.enabled?(:elastomer_reconciler_bypass_mysql_for_progress_calculation, default: true)
      end
    end

    memoize def offset
      get_offset
    end

    # Returns the cached last model ID from Redis. This is used to determine
    # the percent complete value for this reconciler. The value is refreshed
    # only when the cache has expired.
    sig { returns(Integer) }
    def last_id
      cache_expires = redis.hget(group_key, last_id_cache_expires_key)
      return cache_last_id! unless last_id_cache_fresh?(cached_last_id, cache_expires)

      cached_last_id.to_i
    end

    sig { returns(T.nilable(Integer)) }
    memoize def cached_last_id # rubocop:disable GitHub/ControllersShouldUseMemoizeForMemoization
      # Memoized to avoid repeated Redis calls; cache_last_id! updates the memoized value directly via @all_memoized.
      redis.hget(group_key, last_id_key)&.to_i
    end

    def use_limit_execution_time?
      if parent_job.present?
        FeatureFlag.vexi.enabled?(:elastomer_reconciler_use_limit_execution_time, parent_job.class.name, default: true)
      else
        FeatureFlag.vexi.enabled?(:elastomer_reconciler_use_limit_execution_time, default: true)
      end
    end

    # This is a lengthy instrumentation to ensure we properly log, escalate, and safely fall back to a
    # worst-case scenario ID. This unblocks jobs that would otherwise not be able to start due to a killed query
    # when calculating the `last_id`.
    # In this case, we:
    #   - set the `last_id` to the model's maximum id
    #   - log an event in Datadog with relevant tags for filtering and alerting
    #   - log an exception in Failbot for Sentry propagation
    #   - extend the cache expiration to LAST_ID_ERROR_CACHE_TTL to avoid excessive querying until
    #     a much larger chunk of records has been processed.
    sig { params(error: StandardError).returns(Integer) }
    def fallback_to_model_max_id(error)
      max_id = begin
        model_class.maximum(:id).to_i # domain-isolation-query-violation:ignore:packages/issues (SELECT)
      rescue ActiveRecord::StatementTimeout, Timeout::Error => e
        0
      end
      datadog_tags = [
        "index:#{index.name}",
        "model:#{model_class.name}",
      ]

      # Failbot (Sentry) should use otel semantics
      failbot_tags = {
        "db.elasticsearch.path_parts.index": index.name,
        "search.reconciler.model": model_class.name,
      }

      # This slug is used to specify the narrowest possible scope in error/event messages.
      # This should never be present in a tag, because it can be high cardinality.
      scope_slug = self.class.name || ""

      # Builds out the tags and slug based on the actual scope.
      if parent_job.present?
        datadog_tags << "job:#{parent_job.class.name}"
        failbot_tags[:"gh.job.name"] = parent_job.class.name

        datadog_tags << "target_scope:#{parent_job.target_scope}"
        failbot_tags[:"search.repair.target_scope"] = parent_job.target_scope

        scope_slug = "#{scope_slug}:#{parent_job.class.name}"
        if parent_job.target_scope.present?
          scope_slug = "#{scope_slug}:#{parent_job.target_scope}:#{parent_job.target_scope_id}"
        end
      end

      # This is what gets reported to Sentry/Splunk via Failbot
      err = MaximumIdQueryFailedError.new(
        "Maximum ID query timed out for #{scope_slug}, fallback to maximum ID value from model_class.maximum(:id)"
      )
      err.set_backtrace(error.backtrace)

      GitHub.dogstats.event(
        "search.repair.maximum_id_query_timeout",
        "Maximum ID query timed out for #{scope_slug}, fallback to maximum ID value from model_class.maximum(:id)",
        { tags: datadog_tags }
      )

      Failbot.report(err, failbot_tags)

      max_id
    end

    # Cache the current maximum model ID in Redis for use in progress calculation.
    def cache_last_id!
      cache_expires = LAST_ID_CACHE_TTL.from_now.iso8601
      cached_value = begin
        if use_limit_execution_time?
          canonical_scope.where(
            "#{model_class.table_name}.id >= ?", offset
          ).reorder(id: :desc).limit(1).limit_execution_time(limit_ms: @query_timeout).pluck(:id).first.to_i # domain-isolation-query-violation:ignore:packages/issues (SELECT)
        else # Deprecation path:
          timeout_seconds = (@query_timeout / 1000.0).ceil
          Timeout.timeout(timeout_seconds) do
            canonical_scope.where("#{model_class.table_name}.id >= ?", offset).reorder(id: :desc)
              .limit(1).pluck(:id).first.to_i # domain-isolation-query-violation:ignore:packages/issues (SELECT)
          end
        end
      rescue ActiveRecord::StatementTimeout, Timeout::Error => e
        # Extend cache TTL on error; fallback_to_model_max_id computes the value and reports the incident.
        cache_expires = LAST_ID_ERROR_CACHE_TTL.from_now.iso8601
        fallback_to_model_max_id(e)
      end
      redis.hset(group_key, last_id_key, cached_value)
      @all_memoized ||= {}
      @all_memoized[:cached_last_id] = cached_value
      redis.hset(group_key, last_id_cache_expires_key, cache_expires)
      cached_value
    end

    def last_id_cache_fresh?(cached_last_id, cache_expires)
      cached_last_id.present? && cache_expires.present? && Time.now < Time.iso8601(cache_expires)
    rescue ArgumentError
      false
    end

    # Get the last model ID offset from redis.
    #
    # Returns an offset Integer.
    def get_offset
      redis.hget(group_key, offset_key).to_i
    end

    # Internal: Set the offset in redis. This should only be called while
    # guarded by a shared mutex. See the `models` method further down.
    #
    # Returns an integer: the number of fields that were added.
    def set_offset(offset)
      @all_memoized ||= {}
      @all_memoized[:offset] = offset
      redis.hset(group_key, offset_key, offset)
    end

    # Reconcile the state of the documents from the search index with what
    # is in the database. The steps for the reconciliation process are as
    # follows:
    #
    # * get the model reconcile fields from the database
    # * get the document reconcile fields from the search index
    # * compile a list of models to remove from the search index
    # * compile a list of models to update in the search index
    # * perform these operations in a bulk indexing step
    #
    # Returns the Array of model ids to update and remove.
    def reconcile
      GitHub.tracer.in_span("Elastomer::Reconciler#reconcile", attributes: { "type" => @type }, kind: :internal) do
        cache_last_id! unless cached_last_id.present?
        return if models.nil?
        return finish! if models.empty?

        add, update, remove, metadata = generate_actions
        upsert = []

        unless add.empty?
          increment_stats(add_key, add.size)
          upsert.concat add
        end

        unless update.empty?
          increment_stats(update_key, update.size)
          upsert.concat update
        end

        increment_stats(remove_key, remove.size) unless remove.empty?
        increment_stats(total_key, models.size)

        update_search_index(upsert, remove, metadata)

        [add, update, remove] # returning these for debugging purposes
      rescue StandardError, Faraday::TimeoutError => boom
        # When any part of a bulk operation fails, all items in the batch will fail to be indexed.
        increment_stats(error_key, upsert.size + remove.size) if upsert && remove
        Failbot.report(boom.with_redacting!)
        raise if raise_errors
      end
    end

    # Internal: Perform the bulk indexing operations to bring the search
    # index in sync with the database records.
    #
    # upsert   - Array of model IDs to update / add
    # remove   - Array of model IDs to remove
    # metadata - Hash of metadata information for each Elasticsearch document
    #
    # Returns the result of the bulk indexing operation.
    def update_search_index(upsert, remove, metadata)
      GitHub.tracer.in_span("Elastomer::Reconciler#update_search_index") do
        models_hash = models.index_by(&:id)
        adapter_class = ::Elastomer.env.lookup_adapter(es_type)

        type_param = index.client.version_support.es_version_8_plus? ? nil : es_type
        results = T.let(nil, T.untyped)

        log_tags = {
          "gh.elasticsearch.action": :index,
          "db.elasticsearch.path_parts.index": index.name,
          "gh.elasticsearch.document.type": es_type,
        }

        upsert_start = Time.now
        results = index.bulk(request_size: request_size) do |bulk|
          upsert.each do |id|
            GitHub.tracer.in_span("Elastomer::Reconciler#index_document") do
              begin
                model = models_hash[id] || id
                adapter = adapter_class.create(model, adapter_args)
                if doc = adapter.to_hash
                  params = Elastomer::Index.separate_document_and_params(doc, cluster_running_version_8_plus: index.index_running_version_8_plus?)
                  results = bulk.index(doc, params.merge({ _routing: adapter.document_routing }.compact))
                  check_for_errors(results)
                end
              rescue StandardError => boom
                increment_stats(error_key, 1)
                Failbot.report boom,
                  "gh.elasticsearch.action": :index,
                  "db.elasticsearch.path_parts.index": index.name,
                  "gh.elasticsearch.document.type": es_type,
                  "gh.elasticsearch.document.id": id
              end
            end
          end

          upsert_end = Time.now
          upsert_duration = ((upsert_end - upsert_start) * 1000).round(2)
          GitHub.logger.info(
            "Elastomer::Reconciler indexed #{upsert.size} documents for #{@type} in index #{index.name}, ending with ID #{upsert.last} (#{upsert_duration}ms)",
            log_tags
          ) if upsert.any?

          remove_start = Time.now
          remove.each do |id|
            GitHub.tracer.in_span("Elastomer::Reconciler#delete_document") do
              begin
                routing = metadata[id] && metadata[id][:routing]
                params = Elastomer::Index.separate_document_and_params({ _type: type_param, _id: id, _routing: routing }, cluster_running_version_8_plus: index.client.version_support.es_version_8_plus?)
                results = bulk.delete(params)
                check_for_errors(results)
              rescue StandardError => boom
                increment_stats(error_key, 1)
                Failbot.report boom,
                  "gh.elasticsearch.action": :delete,
                  "db.elasticsearch.path_parts.index": index.name,
                  "gh.elasticsearch.document.type": es_type,
                  "gh.elasticsearch.document.id": id
              end

              # Publish to Hydro for pull request deletions (with separate error handling)
              if @type == "pull_request" && FeatureFlag.vexi.enabled?(:publish_pr_es_deletion_to_hydro, default: false)
                begin
                  PullRequestHydroPublisher.publish_changed(
                    pull_request_id: id.to_i,
                    repository_id: routing&.to_i,
                    change: :deleted,
                    index_name: index.name,
                    cluster_name: index.cluster_name,
                    routing_value: routing&.to_s,
                    caller_location: "Elastomer::Reconciler#reconcile",
                    es_result: "deleted",
                    es_version: nil
                  )
                rescue StandardError => e
                  # Don't fail the reconciliation if hydro publishing fails
                  GitHub.logger.warn("Failed to publish PR deletion to Hydro during reconciliation", {
                    pull_request_id: id.to_i,
                    repository_id: routing&.to_i,
                    error: e.message
                  })
                end
              end
            end
          end
          remove_end = Time.now
          remove_duration = ((remove_end - remove_start) * 1000).round(2)

          GitHub.logger.info(
            "Elastomer::Reconciler removed #{remove.size} documents for #{@type} in index #{index.name}, ending with ID #{remove.last} (#{remove_duration}ms)",
            log_tags
          ) if remove.any?
        end
        check_for_errors(results)
      end
    end

    # Internal: Check for errors in the bulk indexing response and report
    # error metrics to our stats endpoint.
    #
    # Returns the `results` passed in to the method
    def check_for_errors(results)
      return results if results.nil? || results["errors"] == false

      errors = 0
      results["items"].each do |item|
        action = item.keys.first
        data   = item.values.first
        next unless data.has_key?("error")
        errors += 1
        raise BulkIndexResponseError.new(data["error"]) if @raise_errors
      end

      increment_stats(error_key, errors) if errors > 0
      results
    end

    # Internal: Helper method that will increment a stats counter in redis
    # identified.
    #
    # field - The redis field holding the stat
    # size  - The increment size
    #
    # Returns the new stat counter value.
    def increment_stats(field, size)
      redis.hincrby(group_key, field, size)

      key = field.split("/").last

      GitHub.dogstats.count("search.repair", size, { tags: ["key:#{key}", "index:#{index.name}"] })
    end

    # Internal: Given two hashes containing record IDs and their reconcile
    # fields, return three Arrays. The first Array contains all the model
    # IDs that need to be added to the search index. The second Array
    # contains all the model IDs that need to be updated in the search
    # index. The third Array contains all the model IDs that need to be
    # removed from the search index.
    #
    # Returns the Array of model IDs to add, update, remove and metadata about
    # existing Elasticsearch documents.
    def generate_actions
      GitHub.tracer.in_span("Elastomer::Reconciler#generate_actions") do
        db_hash = lookup_from_db
        es_hash = @delete_documents_from_es ? lookup_from_es : {}

        db_keys = db_hash.keys
        es_keys = es_hash.keys

        add    = db_keys - es_keys
        remove = es_keys - db_keys

        update = []
        (db_keys & es_keys).each do |key|
          update << key if @force_reindex || db_hash[key] != T.must(es_hash[key])[:fields]
        end

        metadata = {}
        es_hash.each { |id, hash| metadata[id] = hash[:metadata] }

        [add, update, remove, metadata]
      end
    end

    # Internal: Take all the model objects read from the database and return
    # a Hash of the IDs and the reconcile fields.
    #
    # Returns a Hash of ID / reconcile field pairs.
    def lookup_from_db
      GitHub.tracer.in_span("Elastomer::Reconciler#lookup_from_db") do
        return {} if models.empty?

        prefills.each do |method|
          GitHub::PrefillAssociations.prefill_batch_method(models, method)
        end

        hash = Hash.new
        models.each do |model|
          next if     reject.any? { |method| model.method(method).call }
          next unless accept.all? { |method| model.method(method).call }

          begin
            ary = fields.map { |name| model.method(name).call }
            hash[model.id] = (ary.length == 1 ? ary.first : ary)
          rescue StandardError
            # Most models will not error due to `fields` being direct attributes of the model
            # When `fields` are methods instead, ignore errors since those models should not be reconciled
            GitHub.logger.info("Elastomer::Reconciler skipping model due to exception in comparison field", {
              "code.namespace" => self.class.name,
              "code.function" => "lookup_from_db",
              "gh.search.index" => @index&.name,
              "gh.search.model.class" => model.class.name,
              "gh.search.model.id" => model.id,
              "gh.search.model.fields" => fields
            })
          end
        end
        hash
      end
    end

    # Internal: Uses the IDs range from the models list and queries for matching documents that exist in this range of IDs.
    # Custom Elasticsearch queries provided via `named_elasticsearch_queries` and `target_scope` are supported, otherwise
    # all documents in the ID range are queried in batches of up to MAX_ELASTICSEARCH_DOCUMENTS_PER_REQUEST.
    #
    # Returns a Hash of ID / document metadata & reconcile field pairs.
    sig { returns(T::Hash[Integer, T::Hash[Symbol, T.untyped]]) }
    def lookup_from_es
      GitHub.tracer.in_span("Elastomer::Reconciler#lookup_from_es") do
        hash = Hash.new
        return hash if models.empty?

        type_param = index.client.version_support.es_version_8_plus? ? nil : es_type
        current_id_range = id_range.dup

        loop do
          break_on_empty = true
          query = named_elasticsearch_query(current_id_range)
          if query.nil?
            # Only break the loop on an empty result set if a custom query is used
            break_on_empty = false
            query = { query: { ids: { values: current_id_range.take(MAX_ELASTICSEARCH_DOCUMENTS_PER_REQUEST) } } }
            query[:query][:ids][:type] = type_param if type_param
          end

          query[:size] ||= [current_id_range.size, MAX_ELASTICSEARCH_DOCUMENTS_PER_REQUEST].min
          query[:_source] = fields

          search_params = type_param ? { type: type_param } : {}
          if index.respond_to?(:search_all)
            results = index.search_all(query, params: search_params)
          else
            results = index.search(query, search_params)
          end

          hits = results.dig("hits", "hits") || []
          break if hits.empty? && break_on_empty

          # - When executing a query with exact matches on IDs, the max ID in the result set will be
          #   less than or equal to the first requested ID + the query size.  The next query batch should start
          #   at (first requested ID + query size + 1).
          # - When executing a query with inexact matching on IDs, the max ID in the result set is greater than or
          #   equal to the first requested ID + the query size.  The next query batch should start at
          #   (max ID in result set + 1).
          # The max possible ID from both query types can be found as the max of (first requested ID + query size)
          # and (last ID in result set).
          # Set the initial value to the static value (first requested ID + query size) and update as needed
          # while iterating through results.
          max_possible_id_from_query = current_id_range.first + query[:size]

          results["hits"]["hits"].each do |doc|
            id = doc["_id"].to_i
            # The query must return results only within the requested ID range.
            if !current_id_range.cover?(id)
              raise InvalidNamedElasticsearchQueryError, "Elasticsearch repair queries must only return results within the requested ID range"
            end

            max_possible_id_from_query = id if id > max_possible_id_from_query

            source = doc["_source"]

            hash[id] = {
              fields: nil,
              metadata: {
                id:      id,
                index:   doc["_index"],
                routing: doc["_routing"],
              },
            }

            next if source.blank?

            ary = fields.map do |name|
              val = source[name]
              val = Time.parse(val) if val && name =~ /_at\Z/i
              val
            end
            hash[id][:fields] = (ary.length == 1 ? ary.first : ary)
          end

          # If the query has covered the entire ID range, break out of the loop.
          # Otherwise increment the range start and continue querying with the reduced range.
          break if max_possible_id_from_query >= current_id_range.last
          current_id_range = (max_possible_id_from_query + 1..current_id_range.last)
        end

        hash
      end
    end

    # Internal: Returns a custom Elasticsearch query for the given document ID range, if one is defined for
    # the parent job's target scope in `named_elasticsearch_queries`.
    # Otherwise, returns nil.
    sig { params(document_id_range: T::Range[Integer]).returns(T.nilable(T::Hash[Symbol, T.untyped])) }
    def named_elasticsearch_query(document_id_range)
      target_scope = parent_job&.target_scope
      return unless target_scope.present? && named_elasticsearch_queries.key?(target_scope)

      target_id = T.must(parent_job.target_scope_id)
      proc = named_elasticsearch_queries.fetch(target_scope)
      proc.call(target_id, document_id_range)
    end

    # Internal: Read the next set of ActiveRecord models to operate on. This
    # will lock the redis mutex and update the offset when the models are
    # loaded.
    #
    # Returns the Array of ActiveRecord model instances.
    sig { params(offset: Integer).returns(String) }
    def canonical_conditions(offset)
      conds = "#{model_class.table_name}.id > #{model_class.connection.quote(offset)}"
      if conditions.present?
        if conditions.respond_to?(:call)
          condition = conditions.call(self, *proc_args)
          if condition.present?
            conds << " AND #{condition}"
          end
        else
          conds << " AND #{conditions}"
        end
      end
      conds
    end

    def canonical_scope
      scope = model_class
      if parent_job&.target_scope.present? && named_scopes.key?(parent_job.target_scope)
        target_scope = T.must(parent_job.target_scope)
        target_id = T.must(parent_job.target_scope_id)
        proc = named_scopes.fetch(target_scope)
        scope = proc.call(target_id)
      elsif model_scope.respond_to?(:call)
        scope = model_scope.call(scope, *proc_args)
      end
      scope
    end

    def canonical_scope_with_annotations
      canonical_scope.annotate("cross-shard-query-exempted").uniq!(:annotate)
    end

    def canonical_base_query(offset)
      conds = canonical_conditions(offset)
      order = "#{model_class.table_name}.id ASC"
      canonical_scope_with_annotations.where(conds).limit(limit).order(order).joins(joins)
    end

    def models
      return @models unless @models.nil?
      @id_range = nil
      range_start = offset
      model_ids = mutex(queue: :reconciler_models).lock do
        conds = canonical_conditions(range_start)
        values = canonical_base_query(range_start).pluck(:id, *additional_mutex_columns) # domain-isolation-query-violation:ignore:packages/issues
        ids = if values.nil? || values.empty?
          []
        elsif values.is_a?(Integer) # Query returned a single value with no additional columns
          set_offset(values)
          [values]
        elsif values.first.is_a?(Array)  # Query returned multiple rows and multiple columns
          set_offset(values.last.first)  # The :id column is always first
          values.map { |vals| vals.first }
        else # Query returned multiple rows but only a single column
          set_offset(values.last) # The :id column only
          values
        end

        post_process_data = if additional_mutex_columns.any? && !values.nil? && !values.empty?
          if values.is_a?(Integer) || !values.first.is_a?(Array)
            values.is_a?(Integer) ? [[values]] : [values]
          else
            values
          end
        else
          ids
        end

        post_process_plucked_columns(post_process_data)
        ids
      end
      @models = if model_ids.empty?
        []
      else
        includes = ar_includes if ar_includes.present?
        models_ = canonical_scope_with_annotations.where(id: model_ids).joins(joins).preload(includes).order(id: :asc).to_a # domain-isolation-query-violation:ignore:packages/issues
        @id_range = if @delete_documents_from_es
          (range_start + 1)..(models_.last.id)
        else
          models_.map(&:id)
        end
        models_
      end
    rescue GitHub::Redis::Mutex::LockError
      GitHub.dogstats.increment("search.repair.lock_error", { tags: ["index:#{index.name}"] })
      nil
    end

    # Subclasses can override this to add extra columns to the mutex pluck when running fast_models.
    # This allows us to avoid N+1 queries in order to update other keys in redis while holding the mutex.
    sig { overridable.returns(T::Array[Symbol]) }
    def additional_mutex_columns
      []
    end

    # Hook method for subclasses to customize behavior after models are loaded
    # Called with the loaded models array
    def post_process_plucked_columns(models)
      # Default implementation does nothing
    end

    # Internal: The model ID range our ElasticSearch query should use.
    attr_reader :id_range
  end
end
