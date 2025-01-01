# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class RepairAuditLogIndexJob < Elastomer::RepairJob
  ACTIVE_KEY = "active".freeze

  queue_as :index_bulk

  def reconcilers
    return @reconcilers if defined?(@reconcilers)

    @reconcilers = [
      Reconciler.new(
        index:     index,
        primary:   primary,
        group_key: group_key,
        redis:     redis,
      ),
    ]
  end

  # This repair job only has a single reconciler. This is a shorhand method
  # for retrieving that one reconciler from the reconcilers list.
  #
  # Returns the Reconciler instance
  def reconciler
    reconcilers.first
  end

  # Lookup the primary index for the audit log slice that is being repaired.
  # This method will return `nil` if a primary index does not exist for this
  # slice.
  #
  # Returns an `AuditLog` index instance or `nil` if there is no primary index
  # rubocop:todo GitHub/BooleanMemoizationWithOrOperator
  def primary
    @primary ||= begin
                   slicer = Elastomer::Indexes::AuditLog.slicer
                   slicer.fullname = index_name

                   index_config = Elastomer.router.primary(slicer.index, slicer.slice)
                   index_config&.index
                 end
  end
  # rubocop:enable GitHub/BooleanMemoizationWithOrOperator

  # Overrides Elastomer::RepairJob#perform.
  #
  # Perform the actual work of reconciling the audit log search index with
  # the primary search index. This method will check the `enabled` flag and
  # only perform work if the flag is true. This method will enqueue another
  # repair job if there are more iterations to perform.
  #
  # This method also ensures that only a single audit log repair job can be
  # active at any given time. This single job will process the entire
  # primary audit log search index. It is designed to be stopped if needed.
  # The job can be resumed within 10 minutes (do to the Elasticsearch scroll
  # timeout), otherwise it will need to be restarted from the beginning.
  #
  # Returns this repair job instance.
  #
  # Note: this job was recently converted for ActiveJob compatibility, while
  # retaining backcompat with the old search repair API pattern. This means
  # locallying instantiated jobs (or job submit calls via class `perform_*`
  # methods) will still work, but instance-level `perform_*` calls on a
  # deserialized job (such as on a worker pool Aqueduct host) will attempt
  # to pick up and honor directly passed arguments as well.
  #
  # Long-term plan: rewrite these jobs/repair tooling and eliminate the legacy
  # search repair API/flow.
  def perform(name, opts = {})
    if !name.blank?
      @index_name = name
      @job_opts = opts
    end

    return if disabled? || active?

    activate
    until finished?
      break if disabled?
      repair!
    end
  ensure
    deactivate
    requeue if enabled? && !finished?
  end

  # Overrides Elastomer::RepairJob#repair!
  #
  # Perform the actual work of the repairing the search index. This method
  # will execute without checking the `enabled` flag. Only one iteration of
  # the repair job is performed.
  #
  # Use the `perform` method if you want to automatically enqueue another
  # repair job when this one completes. The `perform` method adheres to the
  # `enabled` semantics and will not perform work if the repair job has been
  # disabled.
  #
  # Returns this repair job instance.
  def repair!
    if primary.name == index.name
      reconciler.finish!
      raise ArgumentError, "cannot reindex back into the same audit log search index: #{index.name}"
    end

    super
  end

  # Returns `true` if there is already a repair job running for this
  # particular audit log search index.
  def active?
    1 == redis.hget(group_key, ACTIVE_KEY).to_i
  end

  # Set a key in redis indicating that a worker is processing this audit log
  # search index.
  def activate
    redis.hset(group_key, ACTIVE_KEY, 1)
    self
  end

  # Clear the key in redis indicating that a worker is processing this audit
  # log search index.
  def deactivate
    redis.hset(group_key, ACTIVE_KEY, 0)
    self
  end

  class Reconciler

    NO_PROGRESS_LIMIT = 5
    SCROLL_TIMEOUT = "10m"

    #### Required (these must be supplied via the initializer)

    # The Elastomer::Indexes::AuditLog instance being reconciled.
    attr_reader :index

    # The primary search index where audit log entires will be read from.
    attr_reader :primary

    # The Redis hash key where settings for this reconciler will be stored.
    attr_reader :group_key

    #### Defaults Provided

    # The number of audit log entires to process per iteration (default is 1000).
    attr_reader :limit

    # The Redis connection to use (default is GitHub.job_coordination_redis).
    attr_reader :redis
    private :redis

    # ElasticSearch bulk request size in bytes (default is 512kb).
    attr_reader :request_size

    # Various redis keys
    attr_reader :scroll_key
    attr_reader :document_key
    attr_reader :total_key
    attr_reader :add_key
    attr_reader :update_key
    attr_reader :remove_key
    attr_reader :error_key
    attr_reader :finished_key

    # Create a new Reconciler that will copy the audit log documents from
    # the primary audit log search index slice to the given search index.
    #
    # The primary search index will not be changed by this process. Only the
    # target audit log search index will be updated.
    #
    # The reconcile progress is tracked via several Redis keys. Only a
    # single audit log reconciler should be running per index. The top-level
    # repair job uses an `active` flag to signal that the index is already
    # being reconciled.
    #
    # opts - Options Hash
    #        :index        - Elastomer::Indexes::AuditLog to reconcile
    #        :primary      - primary audit log index to read from
    #        :group_key    - redis hash key
    #        :limit        - number of audit log entries to process
    #        :redis        - the redis connection to use
    #        :request_size - ElasticSearch bulk request size in bytes
    #
    def initialize(opts)
      @index        = opts.fetch(:index)
      @primary      = opts.fetch(:primary)
      @group_key    = opts.fetch(:group_key)

      @limit        = opts.fetch(:limit, 1000)
      @redis        = opts.fetch(:redis, GitHub.job_coordination_redis)
      @request_size = opts.fetch(:request_size, 2.megabytes)

      @scroll_key   = "audit_log/scroll_id"
      @document_key = "audit_log/document"
      @total_key    = "audit_log/total"
      @add_key      = "audit_log/add"
      @update_key   = "audit_log/update"
      @remove_key   = "audit_log/remove"
      @error_key    = "audit_log/error"
      @finished_key = "audit_log/finished"

      @no_progress = 0
      @curr_total  = 0
      @prev_total  = 0
    end

    # Returns the array of stats keys.
    def keys
      [total_key, add_key, update_key, remove_key, error_key, finished_key]
    end

    # Reset the reconciler by clearing all redis keys.
    #
    # Returns this reconciler.
    def reset!
      redis.synchronize do
        redis._client.call([:hdel, group_key, scroll_key, document_key, *keys])
      end
      self
    end

    # Returns `true` if there are no more audit log records to operate on.
    # Returns `false` if there are more audit log records.
    def finished?
      redis.hexists(group_key, finished_key)
    end

    # Internal: Set the finished timestamp in redis to the current time.
    def finish!
      redis.hsetnx(group_key, finished_key, Time.now.iso8601)
    end

    # Returns the progress through the reconciliation task - a floating
    # point number between 0.0 and 100.0. This is the ratio of the current
    # number of copied records to the total number of records in the primary
    # index.
    def progress
      count = get_document_count
      return 0.0 unless count > 0
      (get_progress.to_f / count.to_f) * 100.0
    end

    # Returns the total number documents in the primary index. This
    # information is used in determing the percent complete value for this
    # reconciler.
    def get_document_count
      count = redis.hget(group_key, document_key)

      if count.nil?
        response = primary.client.get("#{primary.name}/_stats/docs")
        count = response.body.dig("_all", "primaries", "docs", "count")
        set_document_count(count)
      end

      count.to_i
    end

    # Set the primary document count in redis.
    #
    # Returns a redis success / error code.
    def set_document_count(count)
      redis.hset(group_key, document_key, count)
    end

    # Get from redis the number of records read from the primary index.
    #
    # Returns an Integer.
    def get_progress
      redis.hget(group_key, add_key).to_i
    end

    # Get the `scroll_id` from redis.
    def get_scroll_id
      redis.hget(group_key, scroll_key)
    end

    # Set the `scroll_id` in redis
    #
    # Returns a redis success / error code.
    def set_scroll_id(scroll_id)
      redis.hset(group_key, scroll_key, scroll_id)
    end

    # Copy the audit log records from the primary audit log index to another
    # search index.
    def reconcile
      setup_slicer
      count = 0
      results = index.bulk(request_size: request_size) do |bulk|
        while count < limit do
          docs = get_primary_records
          break if docs.nil?

          if docs.empty?
            finish!
            break
          end

          docs.each do |doc|
            begin
              count += 1
              source = doc["_source"]
              params = { _id: doc["_id"] }
              unless Elastomer.router.cluster_running_version_8_plus?(GitHub.es_audit_log_cluster)
                params[:_type] = doc["_type"]
              end

              corrected_source = repair_created_at(source)
              results = T.let(bulk.index(corrected_source, params), T.nilable(Hash))
              check_for_errors(results)
            rescue ElastomerClient::Client::Error => boom
              Failbot.report boom,
                bulk_action: "index",
                index:       index.name
            end
          end
        end
      end
      check_for_errors(results)

      @curr_total += count
      increment_stats(add_key, count)

      # if the search context is missing, then our scroll ID has expired
      # the only option here is to mark this repair as "finished" and let the
      # user sort out the problem
    rescue SearchContextMissing => boom
      finish!
      raise boom

    rescue StandardError, TimeoutError => boom # rubocop:todo Lint/GenericRescue
      Failbot.report(boom.with_redacting!)
      check_progress
    end

    def setup_slicer
      @slicer ||= Elastomer::Indexes::AuditLog.slicer
      @slicer.fullname = index.name
    end

    def repair_created_at(source)
      return source if source["@timestamp"]

      case (updated_at = source.dig("data", "updated_at"))
      when String
        updated_at_time = Time.parse(updated_at).utc
        updated_at_ms = Timestamp.from_time(updated_at_time)
      when Integer
        updated_at_ms = updated_at
        updated_at_time = Timestamp.to_time(updated_at_ms).utc
      else
        updated_at_ms = nil
      end

      created_at_ms = source["created_at"]

      # if updated_at and created_at both present
      if updated_at_ms && created_at_ms

        # and if updated_at is valid within slice
        if @slicer.is_entry_date_valid_for_slice?(updated_at_time)
          source["@timestamp"] = updated_at_ms
        end
      else
        created_at_time = Timestamp.to_time(created_at_ms)

        # if created_at is valid within slice
        if @slicer.is_entry_date_valid_for_slice?(created_at_time)
          source["@timestamp"] = created_at_ms
        else
          # use first of the month date since updated_at and created_at
          # either missing or invalid
          source["@timestamp"] = first_of_the_month
        end
      end

      source
    end

    def first_of_the_month
      str = @slicer.slice
      time = @slicer.time_from_value(str)
      Timestamp.from_time(time)
    end

    # Internal: Check for errors in the bulk indexing response and retry any
    # indexing actions that failed. If the indxing fails again, then log an
    # error and continue processing.
    #
    # Returns the `results` passed in to the method
    def check_for_errors(results)
      return results if results.nil? || results["errors"] == false

      errors = 0
      results["items"].each do |item|
        data = item.values.first
        next unless data.has_key?("error")

        type   = data["_type"]
        id     = data["_id"]
        doc    =
          if Elastomer.router.cluster_running_version_8_plus?(GitHub.es_audit_log_cluster)
            primary.client.get("/#{data["_index"]}/_doc/#{id}")
          else
            primary.client.get("/#{data["_index"]}/#{type}/#{id}")
          end
        source = doc["_source"]

        begin
          index.docs(type).index(source, id: id)
        rescue ElastomerClient::Client::Error => err
          errors += 1
          GitHub.dogstats.count("rpc.elasticsearch.error", 1, tags: %W[rpc_operation:store index:#{index.name}])
          log(source.merge("_index" => index.name, "_type" => type, "_id" => id), err)
          Failbot.report(err)
        end
      end

      increment_stats(error_key, errors) if errors > 0
      results
    end

    # Internal: Log the given document and exception. For Enterprise and
    # development we write the document to a file. In production we send the
    # document to Splunk via GitHub::Logger.
    def log(doc, boom)
      json = GitHub::JSON.dump(doc)

      if !GitHub.enterprise? && !Rails.env.development?
        GitHub.logger.error(
          :exception => boom,
          "code.namespace" => self.class.name,
          "code.function" => __method__,
          "elasticsearch.index.name" => doc["_index"],
          "gh.audit_logs.doc" => json
        )
      else
        File.open(log_filename, "a") { |fd| fd.puts(json) }
      end
    end

    # Internal: Returns the filename used to store audit log documents that
    # failed to index properly.
    def log_filename
      @log_filename ||= "#{File.dirname(Rails.configuration.paths["log"].first)}/repair-#{index.name}.errors.log"
    end

    # Internal: This method keeps track of the number of documents added to
    # the new audit log `index`. If that number does not change after a
    # given number of iterations, then we bail out of the repair job. The
    # assumption is that no progress is being made on the repair, and the
    # user needs to intervene.
    #
    # We have linear ramp sleep method in here to give the network or
    # Elasticsearch time to resolve whatever oddity is happening in the
    # moment.
    #
    # Returns this reconciler instance
    def check_progress
      if !progress_made?
        @no_progress += 1
        sleep(0.250 * @no_progress)
      else
        @no_progress = 0
      end

      if abort_on_progress?
        finish!
        raise RuntimeError, "Progress has not been made in #{NO_PROGRESS_LIMIT} iterations - aborting"
      end

      @prev_total = @curr_total
      self
    end

    def progress_made?
      (@curr_total - @prev_total) > 0
    end

    def abort_on_progress?
      @no_progress > NO_PROGRESS_LIMIT
    end

    # Internal: Helper method that will increment a stats counter in redis.
    #
    # field - The redis field holding the stat
    # size  - The increment size
    #
    # Returns the new stat counter value.
    def increment_stats(field, size)
      redis.hincrby(group_key, field, size)

      key = field.split("/").last
      GitHub.dogstats.count("search.repair", size, { tags: ["index:#{index.name}", "key:#{key}"] })
    end

    # Internal: Get the next 50 audit log records from the primary audit log
    # index.
    #
    # Returns an Array of Hashes.
    def get_primary_records
      scroll_id = get_scroll_id

      body = if scroll_id.nil?
        primary.client.start_scroll \
          body:   { query: { match_all: {} }, sort: ["_doc"] },
          index:  primary.name,
          scroll: SCROLL_TIMEOUT,
          size:   50
      else
        primary.client.continue_scroll(scroll_id, SCROLL_TIMEOUT)
      end

      set_scroll_id(body["_scroll_id"])

      hits = body["hits"]
      set_document_count(Elastomer::UpgradeShims.get_total_hits(hits))
      hits["hits"]

    rescue ElastomerClient::Client::RequestError => err
      if err.error && err.error.dig("caused_by", "type") == "search_context_missing_exception" \
          || err.message =~ /SearchContextMissingException/
        raise SearchContextMissing, "No search context found for scroll ID #{scroll_id.inspect}"
      else
        raise err
      end
    end

    # Specific error class raised when an expired scroll context is used
    SearchContextMissing = Class.new ElastomerClient::Client::RequestError

  end
end
