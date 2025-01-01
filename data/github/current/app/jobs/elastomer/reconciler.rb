# typed: true
# frozen_string_literal: true

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

    # The Redis connection to use (default is GitHub.job_coordination_redis).
    attr_reader :redis
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

    # Various redis keys
    attr_reader :offset_key
    attr_reader :total_key
    attr_reader :add_key
    attr_reader :update_key
    attr_reader :remove_key
    attr_reader :error_key
    attr_reader :finished_key
    attr_reader :mutex_key

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
    #        :include      - eager load these AR model assocations (Array of symbols)
    #        :accept       - AR model methods that must be true (Array of symbols)
    #        :reject       - AR model methods that must be false (Array of symbols)
    #        :raise_errors - Raise errors for debuggability in dev and test (default: false)
    #        :proc_args    - The extra parameters to pass to the :conditions proc
    #
    def initialize(opts)
      @index = opts.fetch(:index)
      @type = opts.fetch(:type)
      @group_key = opts.fetch(:group_key)
      @model_class = opts[:model_class]
      if @model_class.nil?
        @model_class = type.tr("-", "_").classify.constantize
      end
      @model_scope = opts[:model_scope]
      @es_type = opts.fetch(:es_type, @type)

      @fields = opts.fetch(:fields, %w[updated_at])
      @force_reindex = opts.fetch(:force_reindex, false)
      @delete_documents_from_es = opts.fetch(:delete_documents_from_es, true)
      @limit = opts.fetch(:limit, 100)
      @redis = opts.fetch(:redis, GitHub.job_coordination_redis)
      @request_size = opts.fetch(:request_size, 512.kilobytes)
      @conditions = opts.fetch(:conditions, nil)
      @joins = opts.fetch(:joins, nil)
      @ar_includes  = opts.fetch(:include, nil)
      @prefills     = opts.fetch(:prefills, [])
      @raise_errors = opts.fetch(:raise_errors, false)
      @proc_args    = opts.fetch(:proc_args, nil)

      @accept       = Array(opts[:accept])
      @reject       = Array(opts[:reject])

      @adapter_args = opts[:adapter_args] || {}

      @offset_key   = "#@type/offset"
      @total_key    = "#@type/total"
      @add_key      = "#@type/add"
      @update_key   = "#@type/update"
      @remove_key   = "#@type/remove"
      @error_key    = "#@type/error"
      @finished_key = "#@type/finished"
      @mutex_key    = "#@type/mutex"
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
      redis.synchronize do
        redis._client.call([:hdel, group_key, offset_key, *keys])
      end
      mutex.unlock!
      remove_instance_variable(:@models) if defined? @models
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

    # Returns the progress through the reconciliation task - a floating
    # point number between 0.0 and 100.0. This is the ratio of the current
    # model ID offset versus the largest model ID.
    def progress
      last = last_id
      return 0.0 unless last > 0
      (get_offset.to_f / last.to_f) * 100.0
    end

    # Returns the last model ID from the database. This information is used
    # in determing the percent complete value for this reconciler.
    def last_id
      model_class.maximum(:id).to_i
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
    # Returns a redis success / error code.
    def set_offset(offset)
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

      [add, update, remove]  # returning these for debugging purposes

    rescue StandardError, Faraday::TimeoutError => boom # rubocop:todo Lint/GenericRescue
      # When any part of a bulk operation fails, all items in the batch will fail to be indexed.
      increment_stats(error_key, upsert.size + remove.size) if upsert && remove
      Failbot.report(boom.with_redacting!)
      raise if raise_errors
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

        upsert_end = Time.now
        upsert_duration = ((upsert_end - upsert_start) * 1000).round(2)
        GitHub.logger.info(
          "Elastomer::Reconciler indexed #{upsert.size} documents for #{@type} in index #{index.name}, ending with ID #{upsert.last} (#{upsert_duration}ms)",
          log_tags
        ) if upsert.any?

        remove_start = Time.now
        remove.each do |id|
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
      db_hash = lookup_from_db
      es_hash = lookup_from_es

      db_keys = db_hash.keys
      es_keys = es_hash.keys

      add    = db_keys - es_keys
      remove = es_keys - db_keys

      update = []
      (db_keys & es_keys).each do |key|
        update << key if @force_reindex || db_hash[key] != es_hash[key][:fields]
      end

      metadata = {}
      es_hash.each { |id, hash| metadata[id] = hash[:metadata] }

      [add, update, remove, metadata]
    end

    # Internal: Take all the model objects read from the database and return
    # a Hash of the IDs and the reconcile fields.
    #
    # Returns a Hash of ID / reconcile field pairs.
    def lookup_from_db
      return {} if models.empty?

      hash = Hash.new
      models.each do |model|
        next if     reject.any? { |method| model.send(method) }
        next unless accept.all? { |method| model.send(method) }

        begin
          ary = fields.map { |name| model.send(name) }
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

    # Internal: Take the first and last model IDs from the models list and
    # query all the documents that exist in this range of IDs. Return the a
    # Hash containing the ID and corresponding reconcile fields as read from
    # the search index.
    #
    # Returns a Hash of ID / document metadata & reconcile field pairs.
    def lookup_from_es
      hash = Hash.new
      return hash if models.empty?

      type_param = index.client.version_support.es_version_8_plus? ? nil : es_type

      id_range.each_slice(2_000) do |id_ary|
        query = {
          query: { ids: type_param ? { type: type_param, values: id_ary } : { values: id_ary } },
          _source: fields,
          size: id_ary.length,
        }

        search_params = type_param ? { type: type_param } : {}

        if index.respond_to?(:search_all)
          results = index.search_all(query, params: search_params)
        else
          results = index.search(query, search_params)
        end

        results["hits"]["hits"].each do |doc|
          id = doc["_id"].to_i
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
      end

      hash
    end

    # Internal: Read the next set of ActiveRecord models to operate on. This
    # will lock the redis mutex and update the offset when the models are
    # loaded.
    #
    # Returns the Array of ActiveRecord model instances.
    def models
      return @models if defined? @models
      @models = nil
      @id_range = nil

      @models = mutex.lock do
        offset = get_offset

        conds = "#{model_class.table_name}.id > #{model_class.connection.quote(offset)}"
        order = "#{model_class.table_name}.id ASC"
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
        includes = ar_includes if ar_includes.present?

        scope = model_class
        if model_scope.respond_to?(:call)
          scope = model_scope.call(scope)
        end
        ary = scope.annotate("cross-shard-query-exempted").uniq!(:annotate).where(conds).limit(limit).order(order).joins(joins).preload(includes).to_a
        unless ary.empty?
          prefills.each do |method|
            GitHub::PrefillAssociations.prefill_batch_method(ary, method)
          end

          set_offset(ary.last.id)
          @id_range = if @delete_documents_from_es
            (offset + 1)..(ary.last.id)
          else
            ary.map &:id
          end
        end
        ary
      end
    rescue GitHub::Redis::Mutex::LockError
      GitHub.dogstats.increment("search.repair.lock_error", { tags: ["index:#{index.name}"] })
      nil
    end

    # Internal: The model ID range our ElasticSearch query should use.
    attr_reader :id_range

    # Internal: Return a shared redis mutex to coordinate access to the
    # shared Repository timestamp.
    #
    # Returns a GitHub::Redis::Mutex instance
    def mutex
      @mutex ||= GitHub::Redis::MutexGroup.new \
                    group_key, mutex_key,
                    timeout: 60, wait: 10, sleep: 1
    end
  end
end
