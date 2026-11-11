# typed: strict
# frozen_string_literal: true

# This job syncs a single issue field with all related project columns, ensuring that the project columns
# are updated with the latest issue field values in the event they become out of sync via the normal aqueduct flow.
# This will update the column if the name has changed, or delete the column if the issue field has been destroyed.
#
# The job leverages the `BatchedJob` framework which helps manage resilience and
# performance when dealing with large datasets.
class SyncIssueFieldToProjectColumnsJob < BatchedJob
  include GitHub::Memoizer
  include ActiveJob::InitiallyEnqueuedAt
  include GitHub::Tracing
  include GitHub::RateLimitable

  BATCH_SIZE = 1000
  DEFAULT_RATE_LIMIT_OPTIONS = T.let({ max_tries: 3, ttl: 5.minutes.to_i }.freeze, T::Hash[Symbol, Integer])

  queue_as :sync_issue_field_to_project_columns

  retry_on WaitForReplication::DataUnavailable do |job, error|
    job.failed(error)
  end

  retry_on_dirty_exit do |job, error|
    job.failed(error)
  end

  retry_on_recoverable_exceptions(wait: 3.seconds) do |job, error|
    job.failed(error)
  end

  around_enqueue do |_job, block|
    next unless syncing_issue_field_column?
    next if apply_rate_limit?
    apply_concurrency_limit!(block)
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
      .returns(T::Array[MemexProjectColumn])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **_options)
    issue_field_id, job_status_id = args

    unless defined?(@job_status)
      @job_status = T.let(
        SyncIssueFieldToProjectColumnsJobStatus.find!(job_status_id),
        T.nilable(SyncIssueFieldToProjectColumnsJobStatus)
      )
    end

    MemexProjectColumn
      .includes(:issue_field)
      .where(issue_field_id:)
      .where("id > ?", offset_item_id)
      .limit(BATCH_SIZE)
      .order(:id)
      .to_a
  end

  sig { override.params(batch: T::Array[MemexProjectColumn], args: T.untyped, options: T.untyped).void }
  def process_batch(batch, *args, **options)
    job_status = T.must(@job_status)
    context = build_job_status_context(job_status, issue_field_id, options[:initial_start])

    batch.each do |column|
      MemexProjectColumn.throttle do
        # Update the column if issue field has been destroyed or the name has changed
        if column.issue_field.nil?
          with_throttled_write(column) do
            column.destroy!
          end
          context.deleted_columns += 1
        elsif column.name != column.issue_field&.name
          MemexProjectColumn.with_issue_field_sync do
            column.denormalize_issue_field(calculate_position: false)
            with_throttled_write(column) do
              column.save!
            end
          end
          context.updated_columns += 1
        else
          context.skipped_columns += 1
        end
      end
    end

    context.reconciled_columns = T.let(
      context.deleted_columns + context.updated_columns,
      Integer
    )
    context.total_columns = T.let(
      context.total_columns.to_i + batch.size,
      Integer
    )

    if !has_next_batch?(batch)
      GitHub.dogstats.count("sync_issue_field_to_project_columns_job.deleted.count", context.deleted_columns, tags: self.all_stats_tags)
      GitHub.dogstats.count("sync_issue_field_to_project_columns_job.updated.count", context.updated_columns, tags: self.all_stats_tags)
      GitHub.dogstats.count("sync_issue_field_to_project_columns_job.skipped.count", context.skipped_columns, tags: self.all_stats_tags)
      GitHub.dogstats.count("sync_issue_field_to_project_columns_job.reconciled.count", context.reconciled_columns, tags: self.all_stats_tags)
      GitHub.dogstats.count("sync_issue_field_to_project_columns_job.evaluated.count", context.total_columns, tags: self.all_stats_tags)
    end

    job_status.context = context.to_h
    with_write { job_status.save }
  end

  sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
  def ensure_perform(finished_successfully:, **options)
    if finished_successfully
      with_write { @job_status&.success! }
      remove_rate_limit_key(rate_limit_key)
      unlock_session
    end
  end

  sig { params(issue_field_ids: T::Array[Integer]).void }
  def self.sync_later(issue_field_ids)
    issue_field_ids.each do |issue_field_id|
      SyncIssueFieldToProjectColumnsJob.perform_later(
        issue_field_id,
        SyncIssueFieldToProjectColumnsJobStatus.create(issue_field_id).id
      )
    end
  end

  sig { params(error: Exception).void }
  private def failed(error)
    parse_job_arguments => { job_status_id: }
    job_status = SyncIssueFieldToProjectColumnsJobStatus.find!(job_status_id)

    remove_rate_limit_key(rate_limit_key)
    with_write { job_status.error!(error.message) }
    unlock_session

    Failbot.report!(error)
  end

  sig { void }
  private def job_skipped
    parse_job_arguments => { job_status_id: }
    job_status = SyncIssueFieldToProjectColumnsJobStatus.find!(job_status_id)
    with_write { job_status.error!("Job skipped because conflicting job is already running") }
  end

  sig do
    params(
      job_status: SyncIssueFieldToProjectColumnsJobStatus,
      issue_field_id: Integer,
      timestamp: T.nilable(Time)
    )
    .returns(SyncIssueFieldToProjectColumnsJobStatus::Context)
  end
  private def build_job_status_context(job_status, issue_field_id, timestamp)
    existing_context = SyncIssueFieldToProjectColumnsJobStatus::Context.from_h(job_status.context)
    return existing_context if existing_context
    SyncIssueFieldToProjectColumnsJobStatus::Context.new(
      issue_field_id:,
      started_at: timestamp&.iso8601
    )
  end

  sig { params(block: T.proc.void).void }
  private def apply_concurrency_limit!(block)
    kv_helper = get_kv_helper

    if session_id.nil?
      session = generate_session_id
      store_session_id(session)
    else
      session = session_id
    end

    kv_session = kv_helper.session_lock

    if kv_session == session
      kv_helper.session_lock = kv_session
      return block.call
    end

    if kv_session.nil?
      lock_session(T.must(session))
      return block.call
    end

    job_skipped
    GitHub.dogstats.increment("sync_issue_field_to_project_columns_job.concurrency_limit.count", tags: self.all_stats_tags)
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

  sig { returns(T::Hash[Symbol, T.untyped]) }
  memoize private def parse_job_arguments
    issue_field_id, job_status_id, options, keywords = self.arguments
    combined_options = (options || {}).merge(keywords || {})
    { issue_field_id:, job_status_id:, options: combined_options }
  end

  sig { returns(T::Boolean) }
  private def first_job?
    parse_job_arguments => { issue_field_id:, options: }
    options.dig(:progress).to_i == 0
  end

  # Returns true if this job should be rate limited, false otherwise.
  #
  # We only apply the rate limit to the first job in the overall sync process for a particular issue field, not
  # the subsequent batched jobs of the field
  sig { returns(T::Boolean) }
  private def apply_rate_limit?
    return false unless first_job?
    rate_limit_increment(rate_limit_key, DEFAULT_RATE_LIMIT_OPTIONS).at_limit?
  end

  sig { returns(T::Boolean) }
  private def syncing_issue_field_column?
    issue_field_id > 0
  end

  sig { returns(KvHelper) }
  private def get_kv_helper
    KvHelper.new(self.class, issue_field_id)
  end

  sig { void }
  private def unlock_session
    get_kv_helper.session_lock = nil
  end

  sig { params(session_id: String).void }
  private def lock_session(session_id)
    get_kv_helper.session_lock = session_id
  end

  sig { returns(String) }
  private def generate_session_id
    SecureRandom.uuid
  end

  sig { returns(String) }
  private def rate_limit_key
    "#{self.class.name}:ratelimit:#{issue_field_id}"
  end

  sig { returns(Integer) }
  private def issue_field_id
    parse_job_arguments[:issue_field_id]
  end

  sig { returns(T.nilable(String)) }
  private def session_id
    parse_job_arguments => { options: }
    options&.fetch(:session_id, nil)
  end

  sig { params(session_id: String).void }
  private def store_session_id(session_id)
    # This intentionally does not use the `parse_job_arguments` helper, because we do not want to merge hash options
    # with keyword arguments in this context.
    issue_field_id, job_status_id, options, keywords = self.arguments

    options ||= {}
    options.merge!(session_id: session_id)

    self.arguments = [issue_field_id, job_status_id, options]
    self.arguments << keywords if keywords.present?
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def trace_tags
    parse_job_arguments => { issue_field_id:, job_status_id:, options: }

    tags = {
      "gh.memex.job.offset_item.id": options[:offset_item_id],
      "gh.memex.job.progress": options[:progress],
      "gh.memex.job.session.id": options[:session_id],
      "gh.memex.sync_issue_field_to_project_columns_job.refresh": options[:refresh],
      "gh.memex.job.initial_start": options[:initial_start]&.try(:iso8601),
      "gh.memex.issue_field.id": issue_field_id,
      "gh.job_status.id": job_status_id,
    }

    tags.compact.stringify_keys
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

  # Each call to `trace_method` here must appear after the definition of the method it instruments
  # in order to workaround a limitation in Sorbet.
  #
  # See https://github.com/sorbet/sorbet/issues/5025#issuecomment-1228146684.
  trace_method :perform, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :next_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :process_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :finalize_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :has_next_batch?, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :ensure_perform, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :failed, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
end
