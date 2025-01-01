# typed: strict
# frozen_string_literal: true

class MemexBatchedBulkAddJob < BatchedJob
  BATCH_SIZE = T.let(50, Integer)
  MAX_ATTEMPTS = T.let(5, Integer)

  class UserNoWriteAccessError < StandardError; end

  # Instance variable we use to store the memex project when processing a batch so that we can access
  # it in ensure_perform to send completion notifications.
  sig { returns(T.nilable(MemexProject)) }
  attr_reader :memex_project_ref

  queue_as :batched_memex_bulk_add
  retry_on_dirty_exit

  RETRYABLE_ERRORS = T.let([
    *Resiliency::Response::UnavailableExceptions,
    Freno::Error,
    Freno::Throttler::WaitedTooLong,
    JobStatus::NotFound,
  ].freeze, T::Array[T.class_of(StandardError)])

  RETRYABLE_ERRORS.each do |error|
    retry_on error, wait: :polynomially_longer, attempts: MAX_ATTEMPTS do |job, error|
      job.report_error(error)
      raise error
    end
  end

  resolve_tenant_context do |memex_id, _rest|
    MemexProject.find_by(id: memex_id)&.resolve_tenant
  end

  sig { returns(String) }
  def self.prefix
    MemexBatchedBulkAddJobStatus::JOB_STATUS_ID_PREFIX
  end

  sig { params(memex_project_id: Integer, user_id: Integer).returns(MemexBatchedBulkAddJobStatus) }
  def self.create_job_status(memex_project_id, user_id)
    MemexBatchedBulkAddJobStatus.create(memex_project_id, user_id)
  end

  sig { params(options: T::Hash[Symbol, T.untyped]).returns(Options) }
  def self.build_options(options)
    Options.new(
      actor_id: options[:actor_id],
      column_data: options[:column_data] || [],
      initial_start: options[:initial_start],
      item_ids: options[:item_ids] || []
    )
  end

  sig do
    params(
      args: T.untyped,
      timestamp: Time,
      offset_item_id: Integer,
      progress: Integer,
      options: T.untyped
    ).returns(T::Array[Issue])
  end
  def next_batch(*args, timestamp: Time.now.utc, offset_item_id: 0, progress: 0, **options)
    memex_project_id, job_status_id = args

    unless defined?(@job_status)
      @job_status = T.let(
        MemexBatchedBulkAddJobStatus.find!(job_status_id),
        T.nilable(MemexBatchedBulkAddJobStatus)
      )
    end

    opts = self.class.build_options(options)
    Issue.where(id: opts.item_ids.sort.select { |id| id > offset_item_id })
      .order(id: :asc)
      .limit(BATCH_SIZE)
      .to_a
  end

  sig do
    params(
      batch: T::Array[Issue],
      args: T.untyped,
      options: T.untyped
    ).void
  end
  def process_batch(batch, *args, **options)
    memex_id, _rest = args
    opts = self.class.build_options(options)
    current_user_id = opts.actor_id
    current_user = T.let(User.find_by(id: current_user_id), T.nilable(User))
    memex_project = T.let(MemexProject.find_by(id: memex_id), T.nilable(MemexProject))
    # Persist for ensure_perform completion callbacks
    @memex_project_ref = T.let(@memex_project_ref, T.nilable(MemexProject)) unless defined?(@memex_project_ref)
    @memex_project_ref = memex_project if memex_project
    unless current_user
      report_error(StandardError.new("No current user given for MemexBatchedBulkAddJob"))
      return
    end
    unless memex_project
      report_error(StandardError.new("No memex project given for MemexBatchedBulkAddJob"))
      return
    end

    job_status = T.must(@job_status)

    # Make the initial 0% progress notification if the context doesn't exist yet, or if the context has 0 total_items added
    ctx = job_status.context
    if ctx.nil? || (ctx[:total_items] == 0)
      notify_clients_of_progress(memex_project, actor_id: opts.actor_id, percentage: 0, request_context: options[:request_context])
    end

    unless memex_project.viewer_can_write?(current_user)
      error = UserNoWriteAccessError.new("User does not have write access to the memex project")
      with_write do
        job_status.error!(error.message)
        job_status.save
      end
      report_error(error)
      raise error
    end

    columns_data = opts.column_data

    added_count = T.let(0, Integer)
    failed_count = T.let(0, Integer)

    issues_promises = batch.map do |issue|
      issue.async_readable_by?(current_user).then do |readable|
        next nil unless readable
        columns_permissions_promises = columns_data.map do |c|
          column_data_type = c[:column]&.data_type&.to_sym
          next Promise.resolve(true) if !c[:column]&.special_type?
          case column_data_type
          when :assignees
            next issue.async_assignable_by?(actor: current_user)
          when :milestone
            next issue.async_can_set_milestone?(current_user)
          when :labels
            next issue.async_labelable_by?(actor: current_user)
          when :parent_issue
            next Promise.resolve(issue.can_add_sub_issue?(actor: current_user, parent_issue_id: c[:value]))
          else
            next Promise.resolve(false)
          end
        end
        next Promise.all(columns_permissions_promises).then do |permissions_results|
          if permissions_results.empty? || permissions_results.all?
            next issue.async_pull_request if issue.pull_request?
            issue
          else
            nil
          end
        end
      end
    end

    issues_results = Promise.all(issues_promises).sync
    failed_count = issues_results.count(&:nil?)

    filtered_issues_or_pulls = T.let(issues_results.compact, T::Array[T.any(Issue, PullRequest)])
    created_items_ids = []
    filtered_issues_or_pulls.each_with_index do |issue_or_pull, _idx|
      MemexProject.throttle do
        item = memex_project.build_item(issue_or_pull:, creator: current_user)
        begin
          with_write do
            item.bulk_operation = true
            memex_project.save_with_priority!(item, **{ position: :bottom })
            columns_data.each do |column|
              item.set_column_value(column[:column], column[:value], current_user)
            end
          end
          added_count += 1
          created_items_ids << item.id
        rescue ActiveRecord::RecordInvalid
          item_duplicated = item.errors.of_kind?(:content_id, :taken)
          if item_duplicated
            archived_item = MemexProjectItem.where(
              repository_id: issue_or_pull.repository_id,
              content: issue_or_pull,
              memex_project: memex_project,
            ).archived.first
            with_write do
              archived_item.bulk_operation = true
              archived_item.unarchive!
            end if archived_item
            added_count += 1
            created_items_ids << archived_item.id if archived_item
          else
            failed_count += 1
          end
        end
      end
    end

    if created_items_ids.any?
      GlobalInstrumenter.instrument("memex_project_item.batched_bulk_add", {
        actor: current_user,
        project: memex_project,
        item_ids: created_items_ids,
        request_context: options[:request_context] || {}
      })
    end

    # Update job status context
    context = build_job_status_context(job_status, memex_id, current_user_id, opts.initial_start).to_h
    context[:total_items] += (added_count + failed_count)
    context[:added_items] += added_count
    context[:failed_items] += failed_count
    job_status.context = context
    with_write do
      job_status.save
    end

    # live update based on overall progress
    total_target = opts.item_ids.size
    percentage = ((context[:total_items].to_f / total_target) * 100).round
    notify_clients_of_progress(memex_project, actor_id: opts.actor_id, percentage: percentage, request_context: options[:request_context] || {})
  end

  sig { override.params(finished_successfully: T::Boolean, options: T.untyped).returns(T.untyped) }
  def ensure_perform(finished_successfully:, **options)
    if finished_successfully
      with_write { @job_status&.success! }
      # Fire completion notification including aggregate counts.
      if @job_status && @memex_project_ref
        ctx = @job_status.context || {}
        added_items = ctx[:added_items] || 0
        notify_clients_of_completion(
          @memex_project_ref,
          actor_id: options[:actor_id],
          added: added_items,
          failed: ctx[:failed_items] || 0,
          request_context: options[:request_context]
        )
      end
    end
  end

  sig do
    params(
      job_status: MemexBatchedBulkAddJobStatus,
      memex_project_id: T.untyped,
      user_id: T.untyped,
      timestamp: T.untyped
    ).returns(MemexBatchedBulkAddJobStatus::Context)
  end
  private def build_job_status_context(job_status, memex_project_id, user_id, timestamp)
    existing_context = MemexBatchedBulkAddJobStatus::Context.from_h(job_status.context)
    return existing_context if existing_context
    MemexBatchedBulkAddJobStatus::Context.new(
      memex_project_id: memex_project_id,
      user_id: user_id,
      started_at: timestamp&.iso8601
    )
  end

  sig { params(error: Exception).void }
  def report_error(error)
    GitHub.logger.error({
      exception: error,
      "gh.job.name": self.class.name,
      "gh.job.id": @job_status&.id,
    })
    Failbot.report(error) if error
  end

  class Options < T::Struct
    const :actor_id, T.nilable(Integer)
    const :column_data, T::Array[T.untyped]
    const :initial_start, T.nilable(Time)
    const :item_ids, T::Array[Integer]
  end

  PROGRESS_MESSAGE_TYPE = T.let("project_items_bulk_add_progress", String)
  COMPLETION_MESSAGE_TYPE = T.let("project_items_bulk_add_complete", String)

  private

  sig do
    params(
      memex_project: MemexProject,
      actor_id: T.nilable(Integer),
      percentage: Integer,
      request_context: T.nilable(T::Hash[Symbol, T.untyped])
    ).void
  end
  def notify_clients_of_progress(memex_project, actor_id:, percentage:, request_context:)
    context = request_context || {}
    memex_project.notify_memex_channel({
      # Keep in sync with client event contract (BulkAddUpdateProgressSocketMessageData)
      type: PROGRESS_MESSAGE_TYPE,
      actor: { id: actor_id },
      percentage: percentage,
      requestId: context[:request_id]
    })
  end

  sig do
    params(
      memex_project: MemexProject,
      actor_id: T.nilable(Integer),
      added: Integer,
      failed: Integer,
      request_context: T.nilable(T::Hash[Symbol, T.untyped])
    ).void
  end
  def notify_clients_of_completion(memex_project, actor_id:, added:, failed:, request_context: {})
    context = request_context || {}
    memex_project.notify_memex_channel({
      type: COMPLETION_MESSAGE_TYPE,
      actor: { id: actor_id },
      totalItemsAdded: added,
      totalItemsFailed: failed,
      requestId: context[:request_id]
    })
  end
end
