# typed: strict
# frozen_string_literal: true

# This background job is used to keep the Elasticsearch index for project items in sync with the latest data
# from canonical sources. Those canonical sources are typically non-Projects-owned MySQL clusters, but they also include
# resources that can only be fetched over HTTP APIs.
#
# The actual resync knowledge is encapsulated in the `MemexProjectItemReconciler` class, but this job layers on some
# useful properties:
#
#   - Batching, so that we can break up the resync of a single project into reasonably sized chunks.
#   - Concurrency control, so that only one resync job can run at a time for a given project.
#   - Status reporting, so that we can track the overall progress of the resync across several constituent job runs.
#   - Rate limiting, so that we don't overwhelm the Elasticsearch cluster, and/or the job queue with too many requests at once.
#
# This class should be used via the `perform_later` class method, which should be given a `MemexProject`` ID as its
# first argument, and a `ResyncMemexProjectItemsIndexJobStatus` ID as its second argument. To perform the
# resync process across all of projects, RepairMemexProjectItemsIndexJob should be used which can be performed
# within the Search settings in Stafftools.
#
# EXAMPLE:
#
#   project = MemexProject.find(123)
#   status = ResyncMemexProjectItemsIndexJobStatus.create(project.id)
#   ResyncMemexProjectItemsIndexJob.perform_later(project.id, status.id)
#
# Optionally enable the `memex_table_without_limits` flag for the given project by passing in `enable_beta_flag: true`
#   ResyncMemexProjectItemsIndexJob.perform_later(project.id, status.id, enable_beta_flag: true)
class ResyncMemexProjectItemsIndexJob < BatchedJob
  include GitHub::Memoizer
  include GitHub::Tracing
  include GitHub::RateLimitable

  queue_as :resync_memex_project_items_search_index

  retry_on WaitForReplication::DataUnavailable do |job, error|
    job.failed(error)
  end

  retry_on_dirty_exit do |job, error|
    job.failed(error)
  end

  retry_on_recoverable_exceptions(wait: 3.seconds) do |job, error|
    job.failed(error)
  end

  BATCH_SIZE = 1000
  DEFAULT_RATE_LIMIT_OPTIONS = T.let({ max_tries: 3, ttl: 5.minutes.to_i }.freeze, T::Hash[Symbol, Integer])

  around_enqueue do |_job, block|
    next if apply_rate_limit?
    apply_concurrency_limit!(block)
  end

  resolve_tenant_context do |project_id|
    project = MemexProject.includes(:owner).find_by(id: project_id)
    project&.resolve_tenant
  end

  sig { params(block: T.proc.void).void }
  def apply_concurrency_limit!(block)
    get_job_key
    session_id = get_session_id
    kv_helper = get_kv_helper

    if session_id.nil?
      session_id = generate_session_id
      store_session_id(session_id)
    end

    kv_session = kv_helper.session_lock

    if kv_session == session_id
      kv_helper.session_lock = kv_session
      return block.call
    end

    if kv_session.nil?
      lock_session(session_id)
      return block.call
    end

    if can_steal_lock?
      kv_helper.session_lock = session_id
      GitHub.dogstats.increment("resync_memex_project_items_index_job.interrupted.count", tags: self.all_stats_tags)
      return block.call
    end

    job_skipped
    GitHub.dogstats.increment("resync_memex_project_items_index_job.skipped.count", tags: self.all_stats_tags)
  end

  # Returns true if this job should be rate limited, false otherwise.
  #
  # We only apply the rate limit to the first job in the overall resync process for a particular project, so that
  # we're rate limiting the resync as a whole rather than its batches.
  sig { returns(T::Boolean) }
  def apply_rate_limit?
    return false unless first_job?
    rate_limit_increment(rate_limit_key, DEFAULT_RATE_LIMIT_OPTIONS).at_limit?
  end

  around_perform do |job, block|
    job.parse_job_arguments => { memex_project_id:, options: }
    Failbot.push("gh.memex.project.id": memex_project_id)
    next block.call if job.read_only?

    if options[:progress].nil?
      # When progress is nil, it means we are processing the first batch. We only want to stamp the start time for the
      # project repair once (rather than for each batch), so we do it here.
      record = MemexProjectElasticsearchConsistency.find_or_initialize_by(memex_project_id:)
      with_throttled_write(record) { record.update!(repair_started_at: Time.now.utc) }
    end
    block.call
  end

  sig do
    override
      .params(
        args: T.untyped,
        timestamp: Time,
        offset_item_id: Integer,
        progress: Integer,
        _options: T.untyped
      )
      .returns(T::Array[MemexProjectItem])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **_options)
    memex_project_id, job_status_id = args

    unless defined?(@job_status)
      @job_status = T.let(
        ResyncMemexProjectItemsIndexJobStatus.find!(job_status_id),
        T.nilable(ResyncMemexProjectItemsIndexJobStatus)
      )
    end

    MemexProjectItem
      .order(:id)
      .where(memex_project_id: memex_project_id)
      .where("id > ?", offset_item_id)
      .limit(BATCH_SIZE)
      .to_a
  end

  sig { override.params(batch: T::Array[MemexProjectItem], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    memex_project_id, _rest = args
    reconciler = Search::MemexProjectItemReconciler.new(memex_project_id, read_only: read_only?)
    job_status = T.must(@job_status)
    context = build_job_status_context(job_status, memex_project_id, options[:initial_start])

    with_write { job_status.started! } if job_status.pending?

    if batch.any?
      # There is some non-zero number of items that need to be reconciled with Elasticsearch,
      # so perform the reconciliation with the current batch.
      result = reconciler.reconcile!(batch, wait_for_refresh: options[:wait_for_refresh], timestamp: options[:initial_start]&.to_i)
      context.reconciled_items += result.total
      context.total_items += batch.length
      context.total_errors += result.errored
    end

    if !has_next_batch?(batch)
      # We just processed the last batch, so clear any items left in Elasticsearch with a higher ID.
      min_item_id = (
        # If the batch was non-empty, take the maximum ID.
        batch.map(&:id).max ||

        # If the batch was empty, then either we batched exactly on a boundary,
        # or there were no items in the project. Either way, the offset the job
        # was called with represents maximum ID we've successfully re-synced.
        options[:offset_item_id]
      ) + 1 # Add one to make sure we don't remove the last thing we successfully re-synced.

      result = reconciler.clear!(
        greater_than_or_equal_to_item_id: min_item_id,
        wait_for_refresh: options[:wait_for_refresh]
      )
      context.reconciled_items += result.total
      context.total_items += result.total
      context.total_errors += result.errored
    end

    job_status.context = context.to_h
    with_write { job_status.save }
  end

  sig { returns(T.nilable(Float)) }
  private def consistency_score
    total_errors = @job_status&.context&.dig(:total_errors).to_i
    total_count = @job_status&.context&.dig(:total_items).to_f
    reconciled_items = @job_status&.context&.dig(:reconciled_items).to_f
    inconsistent_count = if read_only?
      # When comparing with Elasticsearch, count the number of items that need to be added, updated, or removed.
      reconciled_items
    else
      # When writing to Elasticsearch, only items which could not be added, updated, or removed are inconsistent.
      total_errors
    end

    MemexProjectElasticsearchConsistency.consistency_score(
      inconsistent_count:,
      total_count:,
    )
  end

  sig do
    type_parameters(:T)
      .params(
        record: ApplicationRecord::Base,
        block: T.proc.returns(T.type_parameter(:T)))
      .returns(T.type_parameter(:T))
  end
  private def with_throttled_write(record, &block)
    with_write { record.throttle { yield } }
  end

  sig { returns(T.nilable(T::Boolean)) }
  private def save_consistency_score!
    return unless memex_project_id = @job_status&.context&.dig(:memex_project_id)
    return unless consistency = consistency_score

    attrs = { consistency:, evaluated_at: Time.now.utc }
    attrs.merge!(repair_finished_at: Time.now.utc) unless read_only?

    record = MemexProjectElasticsearchConsistency.find_or_initialize_by(memex_project_id:)
    with_throttled_write(record) { record.update!(attrs) }
  end

  sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
  def ensure_perform(finished_successfully:, **options)
    if finished_successfully
      save_consistency_score!
      with_write { @job_status&.success! }
      remove_rate_limit_key(rate_limit_key)
      unlock_session
      enable_feature_flag_for_project if options[:enable_beta_flag]
    end
  end

  sig { params(error: Exception).void }
  def failed(error)
    parse_job_arguments => {job_status_id:}
    job_status = ResyncMemexProjectItemsIndexJobStatus.find!(job_status_id)

    remove_rate_limit_key(rate_limit_key) # allow job to recover from recoverable errors
    with_write { job_status.error!(error.message) }
    unlock_session

    Failbot.report!(error)
  end

  sig { returns(T::Boolean) }
  def read_only?
    parse_job_arguments => {options:}
    options&.fetch(:read_only, nil) == true
  end

  sig { returns(T.nilable(String)) }
  def get_session_id
    parse_job_arguments => {options:}
    options&.fetch(:session_id, nil)
  end

  sig { params(session_id: String).void }
  def store_session_id(session_id)
    # This intentionally does not use the `parse_job_arguments` helper, because we do not want to merge hash options
    # with keyword arguments in this context.
    memex_project_id, job_status_id, options, keywords = self.arguments

    options ||= {}
    options.merge!(session_id: session_id)

    self.arguments = [memex_project_id, job_status_id, options]
    self.arguments << keywords if keywords.present?
  end

  sig { returns(T::Boolean) }
  def can_steal_lock?
    false
  end

  sig { returns(T.untyped) }
  def get_job_key
    self.arguments.first
  end

  sig { returns(KvHelper) }
  def get_kv_helper
    KvHelper.new(self.class, get_job_key)
  end

  sig { void }
  def unlock_session
    kv_helper = get_kv_helper
    kv_helper.session_lock = nil
  end

  sig { params(session_id: String).void }
  def lock_session(session_id)
    kv_helper = get_kv_helper
    kv_helper.session_lock = session_id
  end

  sig { returns(String) }
  def generate_session_id
    SecureRandom.uuid
  end

  sig { returns(String) }
  def rate_limit_key
    "#{self.class.name}:ratelimit:#{get_job_key}"
  end

  sig { void }
  def job_skipped
    parse_job_arguments => {job_status_id:}
    job_status = ResyncMemexProjectItemsIndexJobStatus.find!(job_status_id)
    with_write { job_status.error!("Job skipped because conflicting job is already running") }
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def trace_tags
    # Assign the result of the memoize method call to a variable so that Sorbet recognizes that it is not nil later on
    return {} unless project = memoized_project

    parse_job_arguments => {memex_project_id:, job_status_id:, options:}

    {
      "gh.memex.job.offset_item.id": options[:offset_item_id],
      "gh.memex.job.progress": options[:progress],
      "gh.memex.job.session.id": options[:session_id],
      "gh.memex.resync_memex_project_items_index_job.wait_for_refresh": options[:wait_for_refresh],
      "gh.memex.job.initial_start": options[:initial_start]&.try(:iso8601),
      "gh.memex.project.id": memex_project_id,
      "gh.memex.memex_without_limits_enable_flag": options[:enable_beta_flag],
      "gh.job_status.id": job_status_id,
    }.compact.stringify_keys
  end

  sig { returns(T.nilable(MemexProject)) }
  memoize def memoized_project
    MemexProject.includes(:owner).find_by(id: self.arguments.first)
  end

  sig do
    params(
      job_status: ResyncMemexProjectItemsIndexJobStatus,
      memex_project_id: Integer,
      timestamp: T.nilable(Time)
    )
    .returns(ResyncMemexProjectItemsIndexJobStatus::Context)
  end
  private def build_job_status_context(job_status, memex_project_id, timestamp)
    existing_context = ResyncMemexProjectItemsIndexJobStatus::Context.from_h(job_status.context)
    return existing_context if existing_context
    ResyncMemexProjectItemsIndexJobStatus::Context.new(memex_project_id:, started_at: timestamp&.iso8601)
  end

  # Whether or not this is the first job of the overall resync process.
  sig { returns(T::Boolean) }
  private def first_job?
    parse_job_arguments => {memex_project_id:, options:}
    GitHub.logger.info(
      "Checking whether or not to apply rate limit",
      "code.namespace" => self.class.name,
      "code.function" => "first_job?",
      "gh.memex.project.id" => memex_project_id,
      "gh.job.resync_memex_project_items_index_job.arguments" => self.arguments.to_json,
      "gh.job.resync_memex_project_items_index_job.options" => options.to_json,
    )
    options.dig(:progress).to_i == 0
  end

  # Returns a hash representing a simplified view of the arguments that were passed to this job's `perform` method.
  #
  # We expect two position arguments: `memex_project_id` and `job_status_id`. These are named explicitly in the result
  # hash.
  #
  # Additionally, we expect some options that are spread across a hash argument and ruby keywords. Our production
  # queueing adapter (aqueduct) treats hashes differently from keywords, while our testing queueing adapter does not.
  # To make those two things behave equivalently, we merge the hash and keywords into a single combined hash and
  # return it under the `options` key.
  #
  # This is the preferred method for deriving this job's arguments; plain `self.arguments` should be avoided.
  sig { returns(T::Hash[Symbol, T.untyped]) }
  def parse_job_arguments
    memex_project_id, job_status_id, options, keywords = self.arguments
    combined_options = (options || {}).merge(keywords || {})
    { memex_project_id:, job_status_id:, options: combined_options }
  end

  class KvHelper
    sig { returns(String) }
    attr_reader :session_key

    sig { params(job_class: T::Class[T.anything], key: T.untyped).void }
    def initialize(job_class, key)
      @session_key = T.let("#{job_class.name}:#{key}", String)
    end

    sig { returns(T.nilable(String)) }
    def session_lock
      Memex::KV.store.get(session_key).value { nil }
    end

    sig { params(value: T.nilable(String)).void }
    def session_lock=(value)
      ActiveRecord::Base.connected_to(role: :writing) do
        if value.present?
          Memex::KV.store.set(session_key, value, expires: 5.minutes.from_now)
        else
          Memex::KV.store.del(session_key)
        end
      end
    end

    sig { returns(T.nilable(Time)) }
    def session_ttl
      Memex::KV.store.ttl(session_key).value { nil }
    end
  end

  # As part of enabling the feature for projects on the waitlist, we can kick
  # off this job to re-index the project and its items and only enable the flag
  # once the project resync completes successfully.
  sig { void }
  def enable_feature_flag_for_project
    parse_job_arguments => { memex_project_id: }
    return unless memex_project = MemexProject.find_by(id: memex_project_id)

    with_write do
      unless memex_project.memex_table_without_limits_or_pwl_public_beta_enabled?
        memex_project.enable_feature(:memex_table_without_limits)
      end
    end
  end

  # Each call to `trace_method` here must appear after the definition of the method it instruments
  # in order to workaround a limitation in Sorbet.
  #
  # See https://github.com/sorbet/sorbet/issues/5025#issuecomment-1228146684.
  trace_method :perform, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :next_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :process_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :finalize_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :has_next_batch?, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :ensure_perfom, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :failed, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
end
