# typed: true
# frozen_string_literal: true

class AddToSearchIndexJob < ApplicationJob
  # This job will add a document to the ElasticSearch index. The document is
  # constructed using an 'adapter' based on the document type and the ID of
  # the document in the MySQL database. An adapter is created that knows how
  # to read all the pertinent information from the MySQL database and then
  # format that information into an indexable document. That document is
  # then stored in ElasticSearch.

  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  # This job is operating at the stamp level, so can't be tenant context aware.
  exempt_from_tenant_context_requirement

  ElastomerRetryError = Class.new(StandardError) # Raise this when you want to retry the job.

  ERROR_REASON_MAP = {
    ElastomerRetryError => :es_client_error,
    Redis::CannotConnectError => :redis_cannot_connect_error,
    Redis::TimeoutError => :redis_timeout_error,
    GeoIP2Compat::Error => :geo_ip2_compat_error,
    GitHub::Restraint::UnableToLock => :unable_to_lock,
    Freno::Error => :freno_error,
    Elastomer::ModelMissing => :model_missing,
    WaitForReplication::DataUnavailable => :data_unavailable
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
  retry_on(ElastomerRetryError, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(Redis::CannotConnectError, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(Redis::TimeoutError, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(GeoIP2Compat::Error, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(GitHub::Restraint::UnableToLock, wait: :polynomially_longer, attempts: GitHub.elastomer_index_lock_backoff_attempts) do
     |job, error| job.stats.failed(error.class)
  end
  retry_on(Freno::Error, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  retry_on(Elastomer::ModelMissing, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
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
    def initialize(submitted_at, resolved_service, type)
      @tags = { catalog_service: resolved_service, type: type, exit: :success }
      @millis_since_submitted = ((Time.now.utc - Timestamp.to_time(submitted_at)).to_f * 1_000).to_i
      @start_time = Time.now.utc
    end

    def tag_readonly_static
      @tags[:readonly] = :static
    end

    def tag_readonly_dynamic
      @tags[:readonly] = :dynamic
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

    def report
      tags = @tags.map { |tag, value| "#{tag}:#{value}" }
      GitHub.dogstats.histogram("add_to_search_index.perform.millis_since_submitted", @millis_since_submitted, tags: tags)
      GitHub.dogstats.histogram("add_to_search_index.perform.millis_since_started", ((Time.now.utc - @start_time).to_f * 1_000).to_i, tags: tags)
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

  # The list of document types that should always use a read-replica when
  # making database requests.
  USE_READONLY = Set.new(%w[code commit wiki])

  # How long to wait for replication delay before requeuing a job to retry
  # later, in seconds. This is based on the 95th percentile for indexing job
  # runs (~1sec), and the goal is to balance job throughput when waiting for
  # replication delay.
  MAX_REPLICATION_DELAY_WAIT = 2.0

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
      return unless Search::ClusterStatus.code_search_indexing_enabled?
    end

    @stats = PerformStats.new(submitted_at, logical_service, type)

    # Only one job for this record is allowed to run at a time:
    key = "#{type}-#{id}"
    restraint.lock!(key, RUNNING_JOBS_PER_KEY, JOB_LOCK_TTL) do
      if USE_READONLY.include?(type)
        ActiveRecord::Base.connected_to(role: :reading) { reindex }
        @stats.tag_readonly_static
      else
        WaitForReplication.new(
          submitted_at,
          store_name: adapter.mysql_cluster,
          max_wait_seconds: MAX_REPLICATION_DELAY_WAIT,
        ).wait!

        ActiveRecord::Base.connected_to(role: :reading) { reindex }
        @stats.tag_readonly_dynamic
      end
    end
  rescue ElastomerClient::Client::Error => err
    @stats.tag_failed(:es_client_error, err.class)
    if err.retry?
      report_retry(err)
      raise ElastomerRetryError
    else
      raise err
    end
  rescue GitRPC::ObjectMissing => err
    @stats.tag_failed(:object_missing, err.class)
    report_retry(err)
    options["purge"] = true
    AddToSearchIndexJob.perform_later(type, id, options)
  rescue WaitForReplication::DataUnavailable => err
    @stats.tag_retried(:data_unavailable)
    raise err
  rescue GitHub::Restraint::UnableToLock => err
    @stats.tag_retried(:unable_to_lock)
    raise err
  rescue Freno::Error => err
    @stats.tag_retried(:freno_error)
    raise err
  rescue Redis::TimeoutError => err
    @stats.tag_retried(:redis_timeout_error)
    raise err
  rescue Redis::CannotConnectError => err
    @stats.tag_retried(:redis_cannot_connect_error)
    raise err
  rescue GeoIP2Compat::Error => err
    @stats.tag_retried(:geo_ip2_compat_error)
    raise err
  rescue Elastomer::ModelMissing => err
    @stats.tag_retried(:model_missing)
    raise err
  ensure
    @stats.try(:report)
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
    @restraint ||= GitHub::Restraint.new
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
      "index_type" => arguments[0],
      "document_id" => arguments[1],
      "submitted_at" => submitted_at,
      "request_id" => request_id,
      "purge" =>  purge,
      "guid" => guid,
    })
  end
end
