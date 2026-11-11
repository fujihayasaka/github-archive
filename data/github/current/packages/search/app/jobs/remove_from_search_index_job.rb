# typed: true
# frozen_string_literal: true

require "pull_requests/hydro_publisher"

class RemoveFromSearchIndexJob < ApplicationJob
  # This job is operating at the stamp level, so can't be tenant context aware.
  exempt_from_tenant_context_requirement

  ElastomerRetryError = Class.new(StandardError) # Raise this when you want to retry the job.

  ERROR_REASON_MAP = {
    ElastomerClient::Client::ConnectionFailed => :es_client_error,
    ElastomerClient::Client::MultiDocumentRequestError => :es_client_error,
    ElastomerRetryError => :es_client_error,
  }.freeze

  queue_as :index_high

  include GitHub::ServiceMapping

  retry_on_dirty_exit
  retry_on(ElastomerRetryError, wait: :polynomially_longer, attempts: 8) { |job, error| job.stats.failed(error.class) }
  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # Public: child class to encapsulate stats calls so
  # we can test the publishing via MemoryDogstatsD
  class PerformStats
    def initialize(submitted_at, resolved_service, type, executions)
      @tags = { catalog_service: resolved_service, type: type, exit: :success }
      @tags[:executions] = executions
      @millis_since_submitted = ((Time.now.utc - Timestamp.to_time(submitted_at).utc).to_f * 1_000).to_i
      @start_time = Time.now.utc
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
      millis_since_started = ((Time.now.utc - @start_time).to_f * 1_000).to_i
      GitHub.dogstats.histogram("remove_from_search_index.perform.millis_since_submitted", @millis_since_submitted, tags: tags)
      GitHub.dogstats.histogram("remove_from_search_index.perform.millis_since_started", millis_since_started, tags: tags)
      GitHub.dogstats.distribution("remove_from_search_index.perform.dist.millis_since_submitted", @millis_since_submitted, tags: tags)
      GitHub.dogstats.distribution("remove_from_search_index.perform.dist.millis_since_started", millis_since_started, tags: tags)
    end

    def failed(error_class)
      tag_failed(ERROR_REASON_MAP[error_class], error_class)
      report
    end
  end

  attr_reader :id, :type, :opts, :args, :stats

  # Public: Remove a document from the ElastSearch index.
  #
  # type - The adapter name as a String
  # id   - The numeric ID of the database record
  # args - An optional index name as a String, and an options hash
  #        including Hydro params only available at job enqueue time
  #        (:request_id, :slicing, :routing, etc...)
  #
  # Returns the Hash response from the ElasticSearch server.
  def perform(type, id, *args)
    if type == "code"
      return unless GitHub.use_elastomer_code_search?
      return unless GitHub.code_search_indexing_enabled?
    end

    @type = type
    @id = id
    @args = args
    @opts = @args.extract_options!
    @stats = PerformStats.new(submitted_at, logical_service, type, executions)

    adapter_class = Elastomer.env.lookup_adapter(type)
    adapter = adapter_class.create(id, *args)
    adapter.document_type = type if adapter.respond_to?(:document_type=)

    es_result = Elastomer.remove_from_search_index(adapter, opts)

    # Publish to Hydro after successful ES deletion for pull requests
    if type == "pull_request" || type == "bulk_pull_requests"
      if FeatureFlag.vexi.enabled?(:publish_pr_es_deletion_to_hydro, default: false)
        publish_pull_request_deletion(adapter, id, es_result, type)
      end
    end

    if opts["pushed_at"].present?
      job = self.class.name&.demodulize.underscore.downcase
      tags = {
        job: job,
        content_type: adapter_class.name.demodulize.underscore.downcase,
        catalog_service: logical_service,
      }
      GitHub.dogstats.timing_since("search.indexing.updated_at_to_indexed_at", opts["pushed_at"], tags: tags)
    end
  rescue Elastomer::ModelMissing
    # Publish even when model is missing (already deleted from ES)
    if type == "pull_request" || type == "bulk_pull_requests"
      if FeatureFlag.vexi.enabled?(:publish_pr_es_deletion_to_hydro, default: false)
        publish_pull_request_deletion(adapter, id, { "result" => "not_found" }, type)
      end
    end
    nil # these things happen
  rescue ElastomerClient::Client::Error, ElastomerClient::Client::MultiDocumentRequestError => err
    if err.retry?
      @stats.tag_retried(:es_client_error)
      report_retry(err)
      raise ElastomerRetryError
    else
      @stats.tag_failed(:es_client_error, err.class)
      raise err
    end
  ensure
    @stats.try(:report)
  end

  # Returns the time when this job was submitted from the application.
  def submitted_at
    opts["submitted_at"] ||= Timestamp.from_time(Time.now)
  end

  def report_retry(error)
    job = self.class.name&.demodulize.underscore.downcase
    error_name = error.class.name.demodulize.underscore

    tags = %W[job:#{job} type:#{type} error:#{error_name} catalog_service:#{logical_service}]
    GitHub.dogstats.count("search.indexing.retries", 1, tags: tags)
  end

  def logical_service
    if type&.downcase == "code"
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/es_code_search"
    else
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/search_muddle"
    end
  end

  private

  # Publish PR deletion event to Hydro (handles both individual and bulk deletions)
  def publish_pull_request_deletion(adapter, id, es_result, type)
    # Get caller location and reason from options
    caller_location = opts[:caller_location]

    # Try to get index/cluster info from adapter first, fall back to opts
    index_name = adapter.index&.name || opts[:index_name]
    cluster_name = adapter.index&.cluster_name || opts[:cluster_name]

    # routing_value comes from adapter for individual PRs
    raw_routing_value = adapter.document_routing if adapter.respond_to?(:document_routing)
    raw_routing_value ||= opts[:routing]
    routing_value = raw_routing_value&.to_s

    es_result_str = es_result.is_a?(Hash) ? es_result["result"] : nil
    es_version = es_result.is_a?(Hash) ? es_result["_version"] : nil

    pull_request_id = type == "pull_request" ? id.to_i : nil
    repository_id = type == "bulk_pull_requests" ? id.to_i : @args.first&.to_i # repository_id is the first arg after type and id

    PullRequestHydroPublisher.publish_changed(
        pull_request_id: pull_request_id,
        repository_id: repository_id,
        change: :deleted,
        index_name: index_name,
        cluster_name: cluster_name,
        routing_value: routing_value,
        caller_location: caller_location,
        es_result: es_result_str,
        es_version: es_version
    )
  rescue => e
    # Don't fail the job if hydro publishing fails
    id_key = type == "bulk_pull_requests" ? :repository_id : :pull_request_id
    GitHub.logger.warn("Failed to publish #{type} deletion to Hydro", {
      id_key => id,
      :error => e.message,
    })
  end
end
