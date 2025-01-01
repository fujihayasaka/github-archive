# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class AddToSearchIndexJob < ApplicationJob
  # This job will add a document to the ElasticSearch index. The document is
  # constructed using an 'adapter' based on the document type and the ID of
  # the document in the MySQL database. An adapter is created that knows how
  # to read all the pertinent information from the MySQL database and then
  # format that information into an indexable document. That document is
  # then stored in ElasticSearch.

  # This job is operating at the stamp level, so can't be tenant context aware.
  exempt_from_tenant_context_requirement

  DEDUPE_QUEUE_KEY_PREFIX = "search.indexing.locked_jobs"

  ElastomerRetryError = Class.new(StandardError) # Raise this when you want to retry the job.

  ERROR_REASON_MAP = {
    ActiveRecord::ConnectionNotEstablished => :ar_connection_not_established,
    ActiveRecord::StatementInvalid => :ar_statement_invalid,
    Elastomer::ModelMissing => :model_missing,
    ElastomerClient::Client::ConnectionFailed => :es_client_error,
    ElastomerRetryError => :es_client_error,
    Freno::Error => :freno_error,
    GeoIP2Compat::Error => :geo_ip2_compat_error,
    GitHub::DatabaseQueryDisabler::DatabaseDisabledError => :database_disabled_error,
    GitHub::KV::UnavailableError => :kv_unavailable_error,
    GitHub::Restraint::UnableToLock => :unable_to_lock,
    IO::EAGAINWaitReadable => :redis_timeout_error,
    Redis::ConnectionError => :redis_connection_error,
    Redis::CannotConnectError => :redis_cannot_connect_error,
    Redis::TimeoutError => :redis_timeout_error,
    Resiliency::Response::UnavailableError => :resiliency_unavailable_error,
    SpokesAPI::ResourceExhausted => :spokes_api_rate_limited,
    SpokesAPI::TimedOut => :spokes_api_timed_out,
    SystemCallError => :system_call_error,
    WaitForReplication::DataUnavailable => :data_unavailable,
  }.freeze

  queue_as :index_high

  retry_on_dirty_exit

  # Following the Rails documentation here:
  # https://api.rubyonrails.org/classes/ActiveJob/Exceptions/ClassMethods.html#method-i-retry_on.
  #
  # 8 attempts mean that we wait, before discarding the job because retries have been exhausted, for
  # a total of 4690 seconds at a minimum. This roughly means we wait a total of 1h and ~18 min excluding
  # the random component of the algorithm (an additional 0-15% per wait interval).
  #
  # The purpose of this is that the minimum window should cover any incident we have and that we
  # should not have to replay items manually.
  retry_on_recoverable_exceptions(wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(ElastomerRetryError, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(GeoIP2Compat::Error, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: GitHub.elastomer_index_lock_backoff_attempts) do
     |job, error| job.stats.failed(error.class)
  end
  retry_on(Freno::Error, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(Elastomer::ModelMissing, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(ElastomerClient::Client::ConnectionFailed, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(WaitForReplication::DataUnavailable, wait: :polynomially_longer, attempts: 8) do |job, error|
    job.stats.failed(error.class)
    GitHub.logger.error(
      "Stopped retrying WaitForReplication after exhausting retry attempts", {
        "gh.job.id" => job.id,
        "gh.repo.add_to_search_index_job.type" => job.type,
        "exception.type" => error.class,
        "db.elasticsearch.cluster.name" => error.store_name,
      }
    )
  end

  retry_on(Elastomer::Adapters::PullRequest::MissingCommitInfo, wait: :polynomially_longer, attempts: 5) do |job, _error|
    GitHub.dogstats.increment("pull_request.missing_commit_info_retries_exhausted")
    # retry without attempting to fetch commit info so the rest of the PR info isn't stale
    AddToSearchIndexJob.perform_later(job.type, job.id, job.options.merge(skip_commit_info_on_failure: true))
  end

  include GitHub::ServiceMapping

  class PerformStats
    def initialize(submitted_at, resolved_service, type, executions)
      @tags = { catalog_service: resolved_service, type: type, exit: :success }
      @tags[:executions] = executions
      @millis_since_submitted = ((Time.now.utc - Timestamp.to_time(submitted_at).utc).to_f * 1_000).to_i
      @start_time = Time.now.utc
    end

    def tag_readonly_static
      @tags[:readonly] = :static
    end

    def tag_retried(reason)
      @tags[:exit] = :retry
      @tags[:exit_subtype] = reason
    end

    def tag_failed(reason, error_class)
      @tags[:exit] = :failure
      @tags[:exit_subtype] = reason
      @tags[:error_class] = error_class
    end

    def tag_semantic(value)
      @tags[:semantic] = value
    end

    def report
      tags = @tags.map { |tag, value| "#{tag}:#{value}" }
      millis_since_started = ((Time.now.utc - @start_time).to_f * 1_000).to_i
      GitHub.dogstats.histogram("add_to_search_index.perform.millis_since_submitted", @millis_since_submitted, tags: tags)
      GitHub.dogstats.histogram("add_to_search_index.perform.millis_since_started", millis_since_started, tags: tags)

      GitHub.dogstats.distribution("add_to_search_index.perform.dist.millis_since_submitted", @millis_since_submitted, tags: tags)
      GitHub.dogstats.distribution("add_to_search_index.perform.dist.millis_since_started", millis_since_started, tags: tags)
    end

    def failed(error_class)
      tag_failed(ERROR_REASON_MAP[error_class], error_class)
      report
    end
  end

  # How many concurrent jobs with the same key are allowed. Since this is
  # indexing content, only one at a time per document, please:
  RUNNING_JOBS_PER_KEY = 1

  # How long a running (or crashed) job is allowed to hold onto a lock, in
  # seconds, before it expires and another one takes over.
  JOB_LOCK_TTL = 30.minutes

  # Construct a GUID String for the given job arguments. The GUID string
  # excludes transient values passed into the `options` hash - "retries",
  # "guid", "request_id".
  #
  # type - The adapter name as a String
  # id   - The numeric ID of the database record
  # opts - An options hash
  #
  # Returns a GUID String for this job.
  def self.guid(type, id, opts = {})
    ary = [self.name, type, id, opts.with_indifferent_access.except("submitted_at", "retries", "guid", "request_id")]
    Digest::SHA1.hexdigest(ary.to_json) # rubocop:disable GitHub/InsecureHashAlgorithm
  end

  attr_reader :type    # what kind of record is being indexed
  attr_reader :id      # the id of the record being indexed
  attr_reader :options # the options passed in as arguments
  attr_reader :stats

  # Public: Perform the work of generating the document and indexing it
  # into ElasticSearch.
  #
  # type - The adapter name as a String
  # id   - The numeric ID of the database record
  # opts - An options hash, which may include the following:
  #        "purge"            - set to true to remove any existing data from
  #                             the index before reindexing it
  #        "index", "cluster" - passed on to Elastomer
  #
  # Returns the Hash response from the ElasticSearch server or `nil` if the
  # document could not be stored.
  def perform(type, id, opts = {})
    @type    = type
    @id      = id
    @options = opts.with_indifferent_access
    @stats = nil
    if type == "code"
      return unless GitHub.use_elastomer_code_search?
      return unless GitHub.code_search_indexing_enabled?
    end

    @stats = PerformStats.new(submitted_at, logical_service, type, executions)

    if type == "issue" || type == "bulk_issues"
      set_semantic_tag
    end

    begin
      custom_deduped_restraint(type, id) do
        reindex
        @stats.tag_readonly_static
      end
    end
  rescue ActiveRecord::ConnectionNotEstablished,
    ActiveRecord::StatementInvalid,
    ElastomerClient::Client::ConnectionFailed,
    Elastomer::ModelMissing,
    Freno::Error,
    GeoIP2Compat::Error,
    GitHub::KV::UnavailableError,
    GitHub::Restraint::UnableToLock,
    IO::EAGAINWaitReadable,
    Redis::CannotConnectError,
    Redis::CommandError,
    Redis::ConnectionError,
    Redis::TimeoutError,
    Resiliency::Response::UnavailableError,
    SpokesAPI::ResourceExhausted,
    SpokesAPI::TimedOut,
    SystemCallError,
    WaitForReplication::DataUnavailable => err
    @stats.tag_retried(ERROR_REASON_MAP[err.class])
    report_retry(err)
    raise err
  rescue ElastomerClient::Client::Error => err
    if err.retry?
      @stats.tag_retried(:es_client_error)
      report_retry(err)
      raise ElastomerRetryError
    else
      @stats.tag_failed(:es_client_error, err.class)
      raise err
    end
  rescue GitRPC::ObjectMissing => err
    @stats.tag_failed(:object_missing, err.class)
    report_retry(err)
    options["purge"] = true
    AddToSearchIndexJob.perform_later(type, id, options)
  ensure
    @stats.try(:report)
  end


  # The implementation of GitHub::Restraint doesn't allow for some of the
  # fine-grained queueing logic that we need, but duplicating some of that logic
  # to a different context would add more redis queries than we need to be executing.
  # This deduped restraint uses the same redis cluster as GitHub::Restraint,
  # but implements logic to only enqueue 1 extra job for a given document,
  # if a job has already locked the document for indexing.

  def custom_deduped_restraint(document_type, document_id, &block)
    document_key = "#{self.class.name}-#{document_type}-#{document_id}"
    if ignore_duplicated_locked_reindex_requests?(document_type)
      unflushed_count = incr_duplicated_locked_reindex_attempts_count(document_key)
      if unflushed_count == RUNNING_JOBS_PER_KEY
        block.call
      elsif unflushed_count == RUNNING_JOBS_PER_KEY + 1
        # Causes a retry for the document
        raise GitHub::Restraint::UnableToLock
      else
        # Silently ignore the request since there is already an unflushed job in the queue
        GitHub.logger.info({
          "gh.job.name" => self.class.name,
          "gh.elasticsearch.document.id" => document_id,
          "gh.elasticsearch.document.type" => document_type,
          "gh.elasticsearch.action" => "index",
          "gh.elasticsearch.document.locked_reindex_attempts" => unflushed_count,
          "message" => "Ignoring duplicate reindex request for #{document_key}",
        })
      end
    else
      # Use default GitHub::Restraint logic if dedupe feature is disabled
      restraint.lock!(document_key, RUNNING_JOBS_PER_KEY, JOB_LOCK_TTL) { block.call }
    end
  end

  # Public: not wired up with GitHub::ServiceMapping, used directly (for now)
  def logical_service
    if type&.downcase == "code"
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/es_code_search"
    else
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/search_muddle"
    end
  end

  # Internal: reindex the document
  def reindex
    if options["purge"] && adapter.respond_to?(:delete_query)
      Elastomer.remove_from_search_index(adapter, options)
    end

    hydrated_at = Time.now.utc
    Elastomer.add_to_search_index(adapter, options)
    if options["pushed_at"].present?
      job = self.class.name&.demodulize.underscore.downcase
      tags = ["job:#{job}", "catalog_service:#{logical_service}"]
      GitHub.dogstats.timing_since("search.indexing.updated_at_to_indexed_at", options["pushed_at"], tags: tags)
    end
  ensure
    # If the running job fails due to an error, we still make sure to
    # clear the dedupe key so that either a retry or another queued job
    # can try again. Otherwise, a failed job would stay locked until the lock expires.
    # Therefore, you should be very careful if mocking this reindex method;
    # instead, prefer mocking Elastomer.add_to_search_index.
    clear_dedupe_key(self.class.document_key(adapter.document_type, adapter.document_id))
  end

  # Internal: the elastomer adapter for the record
  def adapter
    unless defined? @adapter
      adapter_class = Elastomer.env.lookup_adapter(type)
      @adapter = adapter_class.create(id, options)
    end
    @adapter
  end

  # Returns the number of retries that have been attempted for this job.
  def retries
    options["retries"]
  end

  # Returns the GUID String for this particular job instance.
  def guid
    options["guid"] ||= self.class.guid(type, id, options)
  end

  # Returns the time when this job was submitted from the application.
  def submitted_at
    options["submitted_at"] ||= Timestamp.from_time(Time.now)
  end

  # Internal: a concurrency restraint using redis
  def restraint
    @restraint ||= GitHub::Restraint.new(actor: job_class_actor)
  end

  def report_retry(error)
    job = self.class.name&.demodulize.underscore.downcase
    error_name = error.class.name.demodulize.underscore

    tags = %W[job:#{job} type:#{type} error:#{error_name} catalog_service:#{logical_service}]
    GitHub.dogstats.count("search.indexing.retries", 1, tags: tags)
  end

  def logging_context
    # arguments passed includes type, id, and options hash
    kwargs = arguments[2] || {}
    submitted_at, request_id, purge, guid = kwargs.values_at("submitted_at", "request_id", "purge", "guid")

    super.merge({
      "gh.elasticsearch.document.type" => arguments[0],
      "gh.elasticsearch.document.id" => arguments[1],
      "gh.elasticsearch.action" => "index",
      "gh.elasticsearch.action.purge" => purge,
      "index_type" => arguments[0],
      "document_id" => arguments[1],
      "submitted_at" => submitted_at,
      "request_id" => request_id,
      "purge" =>  purge,
      "guid" => guid,
    })
  end

  def self.dedupe_queue_key(document_key)
    "#{DEDUPE_QUEUE_KEY_PREFIX}:#{document_key}"
  end

  def self.document_key(document_type, document_id)
    "#{self.name}-#{document_type}-#{document_id}"
  end

  private

  # Internal: Set the semantic tag based on feature flag for issue and bulk_issues types
  def set_semantic_tag
    return unless FeatureFlag.vexi.enabled?(:copilot_semantic_indexing_tag_semantic, default: false)

    semantic_enabled = case type
    when "issue"
      issue = adapter.issue
      return unless issue&.repository
      FeatureFlag.vexi.enabled?(:copilot_semantic_indexing_source_fields, [issue.repository, issue.repository.owner], default: false)
    when "bulk_issues"
      repo = adapter.repo
      return unless repo
      FeatureFlag.vexi.enabled?(:copilot_semantic_indexing_source_fields, [repo, repo.owner], default: false)
    else
      false
    end

    @stats.tag_semantic(semantic_enabled)
  end

  def clear_dedupe_key(document_key)
    key = self.class.dedupe_queue_key(document_key)
    redis.del(key)
  end

  def redis
    GitHub.new_job_coord_redis
  end

  def incr_duplicated_locked_reindex_attempts_count(document_key)
    key = self.class.dedupe_queue_key(document_key)
    # Optimizes this to be atomic and also issue only one network transaction,
    # preventing a race condition on distributed redis clusters.
    # This script will set the counter to 0 with an expiration if it does not exist,
    # and then increment it in all cases, returning the incremented value.
    script = <<~LUA
      if redis.call('SETNX', KEYS[1], 0) == 1 then
        redis.call('EXPIRE', KEYS[1], ARGV[1])
      end
      return redis.call('INCR', KEYS[1])
    LUA

    redis.eval(script, keys: [key], argv: [JOB_LOCK_TTL.to_i])
  end

  def ignore_duplicated_locked_reindex_requests?(document_type)
    FeatureFlag.vexi.enabled?(
      :ignore_duplicated_locked_reindex_requests,
      document_type,  # allows us to control behavior to only hit certain document types
      default: false
    )
  end
end
