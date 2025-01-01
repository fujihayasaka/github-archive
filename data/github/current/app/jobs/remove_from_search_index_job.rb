# typed: true
# frozen_string_literal: true

class RemoveFromSearchIndexJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  # This job is operating at the stamp level, so can't be tenant context aware.
  exempt_from_tenant_context_requirement

  queue_as :index_high

  include GitHub::ServiceMapping

  retry_on_dirty_exit
  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # Public: child class to encapsulate stats calls so
  # we can test the publishing via MemoryDogstatsD
  class PerformStats
    def initialize(job_class, resolved_service, adapter_class)
      @tags = {
        job: job_class.name.demodulize.underscore.downcase,
        content_type: adapter_class.name.demodulize.underscore.downcase,
        catalog_service: resolved_service,
      }
    end

    def timing_since(key, start_time)
      GitHub.dogstats.timing_since(key, start_time, tags: @tags)
    end
  end

  attr_reader :id, :type, :opts, :args

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
      return unless Search::ClusterStatus.code_search_indexing_enabled?
    end

    @type = type
    @id = id
    @args = args
    @opts = @args.extract_options!

    adapter_class = Elastomer.env.lookup_adapter(type)
    adapter = adapter_class.create(id, *args)
    adapter.document_type = type if adapter.respond_to?(:document_type=)
    statter = PerformStats.new(self.class, logical_service, adapter_class)

    Elastomer.remove_from_search_index(adapter, opts)
    if opts["pushed_at"].present?
      statter.timing_since("search.indexing.updated_at_to_indexed_at", opts["pushed_at"])
    end

  rescue Elastomer::ModelMissing
    nil  # these things happen
  end

  def logical_service
    if type&.downcase == "code"
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/es_code_search"
    else
      "#{::GitHub::ServiceMapping::SERVICE_PREFIX}/search_muddle"
    end
  end

end
