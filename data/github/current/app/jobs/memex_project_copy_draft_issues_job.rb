# typed: strict
# frozen_string_literal: true

class MemexProjectCopyDraftIssuesJob < BatchedJob
  include GitHub::Memoizer
  include GitHub::Tracing

  RETRYABLE_ERRORS = T.let([
    GitHub::Prioritizable::Context::LockedForRebalance,
    ActiveRecord::RecordNotFound, # replication lag
    ActiveRecord::Deadlocked, # DB deadlock
    Freno::Throttler::Error, # Freno throttler errors
    GitHub::Restraint::UnableToLock,
    *Resiliency::Response::UnavailableExceptions, # Recoverable exceptions
  ].freeze, T::Array[T.class_of(StandardError)])

  queue_as :memex_project_copy_draft_issues
  retry_on_dirty_exit

  resolve_tenant_context do |args|
    project = MemexProject.includes(:owner).find_by(id: args[:target_memex_project_id])
    project&.resolve_tenant
  end

  BATCH_SIZE = 50

  # Limit the number of jobs that will run concurrently for a source project
  CONCURRENT_JOBS_LIMIT = 1

  # Capture any unhandled exceptions so that we can notify the user that the job did not complete successfully.
  discard_on(StandardError) do |job, error|
    job.failed(error)
  end

  # Workaround for https://sorbet.org/docs/error-reference#7019
  T.unsafe(self).retry_on(*RETRYABLE_ERRORS, wait: :polynomially_longer, attempts: 5) do |job, error|
    job.failed(error)
  end

  locked_by timeout: 5.minutes, key: DEFAULT_LOCK_PROC

  sig do
    override.params(
      batch: T::Array[MemexProjectItem],
      options: T.untyped
    ).returns(T::Boolean)
  end
  def has_next_batch?(batch, **options)
    cache_data = T.must(get_cache_data)
    items_processed = cache_data.items_processed_count
    batch.size >= BATCH_SIZE && items_processed < MemexProject::Copier.get_max_copy_count && cache_data.max_execution_time > Time.now.to_i
  end

  sig { override.params(batch: T::Array[MemexProjectItem], args: T.untyped, progress: Integer, options: T.untyped).void }
  def finalize_batch(batch, *args, progress:, **options)
    unless has_next_batch?(batch, progress:, **options)
      notify_memex_channel(success: true)
    end
  end

  around_perform do |_job, block|
    if actor.nil?
      invalid_paramaters("Actor not found")
      next
    end

    if source_memex_project.nil?
      invalid_paramaters("Source project not found")
      next
    end

    unless T.must(source_memex_project).viewer_can_read?(actor)
      invalid_paramaters("Actor cannot read source project")
      next
    end

    if target_memex_project.nil?
      invalid_paramaters("Target project not found")
      next
    end

    unless T.must(target_memex_project).viewer_can_write?(actor)
      invalid_paramaters("Actor cannot write to target project")
      next
    end

    cache_data = get_cache_data

    if cache_data.nil?
      invalid_paramaters("Cache data not found")
      next
    end

    block.call
  end

  sig do
    params(
      args: T.untyped,
      offset_item_id: Integer,
      kwargs: T.untyped,
    ).returns(T::Array[MemexProjectItem])
  end
  def next_batch(*args, offset_item_id:, **kwargs)
    T.must(source_memex_project)
      .memex_project_items
      .is_draft
      .not_archived
      .where("id > ?", offset_item_id)
      .order(:id)
      .includes(:memex_project_column_values, :content)
      .limit(BATCH_SIZE)
      .to_a
  end

  sig do
    params(
      records: T::Array[MemexProjectItem],
      args: T.untyped,
      source_memex_project_id: Integer,
      target_memex_project_id: Integer,
      kwargs: T.untyped,
    ).void
  end
  def process_batch(records, *args, source_memex_project_id:, target_memex_project_id:, **kwargs)
    with_restraint(source_memex_project_id) do
      return if records.empty?

      GitHub.logger.info(
        "Processing batch of memex items",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.memex.job.batch_size": records.size,
      )

      draft_issue_builder = MemexProject::Copier::DraftIssueCopyBuilder.new(
        source_project: T.must(source_memex_project),
        target_project: T.must(target_memex_project)
      )

      cache_data = T.must(get_cache_data)
      while Time.now.to_i < cache_data.max_execution_time.to_i
        records.each do |source_draft_issue|
          # If this job was retired from a recoverable exception, we may have already processed this item.
          if cache_data.last_processed_item_id && T.must(source_draft_issue.id) <= T.must(cache_data.last_processed_item_id)
            GitHub.dogstats.increment("memex.memex_project_copy_draft_issues_job.already_processed")
            next
          end

          if cache_data.items_processed_count >= MemexProject::Copier.get_max_copy_count
            next
          end

          target_draft_issue = draft_issue_builder.build_draft_issue_copy(source_draft_issue)

          with_write do
            MemexProjectItem.throttle_with_retry do
              # Prevent updating the updated_at timestamp immediately after saving the new item.
              # This is implemented to reduce queries.
              MemexProjectItem.no_touching do
                begin
                  T.must(target_memex_project).save_with_priority!(target_draft_issue, position: :bottom)
                  cache_data.increment_last_processed_id!(T.must(source_draft_issue.id))
                rescue GitHub::Prioritizable::Context::LockedForRebalance
                  item_failed("locked for rebalance")
                  raise
                rescue ActiveRecord::RecordInvalid => e
                  item_failed("record invalid")
                  cache_data.increment_last_processed_id!(T.must(source_draft_issue.id))
                end
              end
            end
          end
        end
        break
      end

      if cache_data.items_processed_count >= MemexProject::Copier::MAX_DRAFT_COPY_COUNT
        GitHub.dogstats.increment("memex.memex_project_copy_draft_issues_job.reached_limit")

        GitHub.logger.warn("Reached copy draft limit", {
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        })
      end

      if Time.now.to_i >= cache_data.max_execution_time.to_i
        GitHub.dogstats.increment("memex.memex_project_copy_draft_issues_job.max_execution_time_reached")

        GitHub.logger.warn("Reached max execution time", {
          "code.namespace" => self.class.name,
          "code.function" => "perform",
        })
      end

      GitHub.logger.info(
        "Done processing batch of memex items",
        "code.namespace": self.class.name,
        "code.function": __method__,
        "gh.memex.job.batch_size": records.size,
      )
    end
  end

  sig { params(source_memex_project_id: Integer, blk: T.proc.void).void }
  def with_restraint(source_memex_project_id, &blk)
    lock_key = "#{self.class.name}-#{source_memex_project_id}"
    restraint = GitHub::Restraint.new
    restraint.lock!(lock_key, CONCURRENT_JOBS_LIMIT, 5.minutes) do
      yield
    end
  end

  sig { params(error: Exception).void }
  def failed(error)
    notify_memex_channel(success: false)
  end

  sig { params(reason: String).void }
  def invalid_paramaters(reason)
    GitHub.dogstats.increment("memex.memex_project_copy_draft_issues_job.invalid_paramaters", tags: ["reason:#{reason}"])

    GitHub.logger.warn("Invalid parameters", {
      "code.namespace" => self.class.name,
      "code.function" => "invalid_paramaters",
      "gh.memex.job.skip_reason" => reason,
    })
  end

  sig { params(reason: String).void }
  def item_failed(reason)
    GitHub.dogstats.increment("memex.memex_project_copy_draft_issues_job.copy_item_failed", tags: ["reason:#{reason}"])

    GitHub.logger.warn("Copying draft issue failed", {
      "code.namespace" => self.class.name,
      "code.function" => "item_failed",
      "gh.memex.job.failure_reason" => reason,
    })
  end

  sig { returns(T::Hash[String, T.untyped]) }
  def trace_tags
    {
      "gh.memex.job.source_memex_project.id" => source_memex_project&.id,
      "gh.memex.job.target_memex_project.id" => target_memex_project&.id,
      "gh.memex.job.offset_item.id" => arguments.dig(0, :offset_item_id),
      "gh.memex.job.initial_start" => arguments.dig(0, :initial_start)&.try(:iso8601),
      "gh.memex.job.progress" => arguments.dig(0, :progress),
      "gh.actor.id" => actor&.id,
    }.compact
  end

  sig { returns(T::Hash[T.any(String, Symbol), T.untyped]) }
  def logging_context
    super.merge(trace_tags)
  end

  sig { params(success: T::Boolean).void }
  def notify_memex_channel(success:)
    MemexProject::Copier::DraftIssueCopyNotifier.new(
      target_project: T.must(target_memex_project),
      actor: T.must(actor),
      success: success,
    ).notify_memex_channel
  end

  sig { returns(T.nilable(KvHelper)) }
  def get_cache_data
    target_memex_project_id = arguments.dig(0, :target_memex_project_id)
    status = KvHelper.find!(target_memex_project_id)
    if !status
      status = KvHelper.new(target_memex_project_id)
      status.save!
    end
    status
  end

  sig { returns(T.nilable(MemexProject)) }
  memoize def source_memex_project
    source_memex_project_id = arguments.dig(0, :source_memex_project_id)
    MemexProject.find_by(id: source_memex_project_id)
  end

  sig { returns(T.nilable(MemexProject)) }
  memoize def target_memex_project
    target_memex_project_id = arguments.dig(0, :target_memex_project_id)
    MemexProject.find_by(id: target_memex_project_id)
  end

  sig { returns(T.nilable(User)) }
  memoize def actor
    actor_id = arguments.dig(0, :actor_id)
    User.find_by(id: actor_id)
  end

  class KvHelper
    include Memex

    CACHE_DURATION = T.let(24.hours, ActiveSupport::Duration)
    CACHE_PREFIX = "MemexProjectCopyDraftIssuesJob"

    sig { returns(T.nilable(Integer)) }
    attr_reader :last_processed_item_id

    sig { returns(Integer) }
    attr_reader :items_processed_count, :max_execution_time

    sig { params(target_memex_project_id: Integer).returns(T.nilable(KvHelper)) }
    def self.find!(target_memex_project_id)
      json = Memex::KV.store.get("#{CACHE_PREFIX}:#{target_memex_project_id}").value!
      return nil unless json
      self.new(target_memex_project_id, JSON.parse(json, { symbolize_names: true }))
    end

    sig { params(target_memex_project_id: Integer, data: T::Hash[Symbol, T.untyped]).void }
    def initialize(target_memex_project_id, data = {})
      @target_memex_project_id = target_memex_project_id
      @last_processed_item_id = T.let(data[:last_processed_item_id], T.nilable(Integer))
      @items_processed_count = T.let(data[:items_processed_count] || 0, Integer)
      @max_execution_time = T.let(data[:max_execution_time] || 10.minutes.from_now.to_i, Integer)
    end

    sig { params(last_processed_item_id: Integer).void }
    def increment_last_processed_id!(last_processed_item_id)
      @last_processed_item_id = last_processed_item_id
      @items_processed_count = @items_processed_count + 1
      save!
    end

    sig { returns(String) }
    def to_json
      JSON.generate(self.as_json)
    end

    sig { returns(T::Hash[String, T.untyped]) }
    def as_json
      {
        last_processed_item_id: last_processed_item_id,
        items_processed_count: items_processed_count,
        max_execution_time: max_execution_time,
      }
    end

    sig { void }
    def save!
      ActiveRecord::Base.connected_to(role: :writing) do
        Memex::KV.store.set("#{CACHE_PREFIX}:#{@target_memex_project_id}", to_json, expires: CACHE_DURATION.from_now)
      end
    end
  end

  trace_method :perform, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :next_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :process_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :finalize_batch, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :has_next_batch?, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
  trace_method :ensure_perfom, span_attribute_extractor: -> (job, *_args, **_kwargs) { job.trace_tags }
end
