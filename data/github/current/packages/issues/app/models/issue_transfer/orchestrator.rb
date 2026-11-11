# typed: true
# frozen_string_literal: true

# Orchestrates a transfer of issues in bulk with concurrency.
# It is meant to be initiaited in a garage instance.
# More info here: https://github.com/github/issues/issues/2492#issuecomment-1078037679
class IssueTransfer::Orchestrator
  DEFAULT_SETTINGS = {
    batch_size: 500,
    concurrent_jobs_count: 18,
    max_replication_lag: 1.0, # seconds
    max_throttle_retries: 5,
    graph: {}
  }

  attr_reader :graph, :hot_issues, :completed, :settings
  attr_reader :actor, :old_repository, :new_repository

  def initialize(old_repository, new_repository, actor, settings = {})
    @old_repository = old_repository
    @new_repository = new_repository
    @actor = actor

    validate_params

    @settings = DEFAULT_SETTINGS.merge(settings)
    @graph = IssueTransfer::CrossReferencesGraph.from_repo(old_repository.id, @settings[:graph])
    @hot_issues = Hash.new { |h, k| h[k] = {} }
    @completed = Hash.new
  end

  def validate_params
    raise "actor must have write permissions on new repository" unless new_repository.resources.contents.writable_by?(actor)
    raise "actor must have write permissions on old repository" unless old_repository.resources.contents.writable_by?(actor)
    raise "cannot transfer from private to public repository" if old_repository.private? && new_repository.public?
    raise "cannot transfer cross-org" if old_repository.owner != new_repository.owner
  end

  def batch_size
    @settings[:batch_size]
  end

  def max_replication_lag
    @settings[:max_replication_lag]
  end

  def concurrent_jobs_count
    @settings[:concurrent_jobs_count]
  end

  def transfer_issues!
    Rails.logger.info "#{@graph.ids.size} issues will be transferred in batches of #{batch_size} to #{new_repository.name}"
    Rails.logger.info "Using #{concurrent_jobs_count} concurrent jobs"

    log_time "transferring issues" do
      GitHub::RateLimitedCreation.disable_content_creation_rate_limits do
        create_all_transfers!
        copy_issue_bodies!
        process_transfers_in_batches!
      end
    end
  end

  def finished?
    completed.size == graph.ids.size
  end

  def create_batch
    batch = IssueTransfer::Batch.new(old_repository, new_repository, actor, concurrent_jobs_count)

    @graph.ids.each do |issue_id|
      next if completed.has_key?(issue_id)

      if is_cold?(issue_id)
        batch.issue_ids << issue_id

        # mark neighbors as hot, so that we won't transfer them in parallel
        # (otherwise, we might create conflicts).
        mark_neighbors_as_hot(issue_id)
      end

      break if batch.size == batch_size
    end

    batch
  end

  def complete_batch(batch)
    now = Time.now

    batch.issue_ids.each do |issue_id|
      completed[issue_id] = true
    end

    cooled_issues = []

    @hot_issues.each_entry do |issue_id, _|
      # if an issue was hot before, mark it as "lukewarm" now, to indicate that it needs
      # a moment to cool down, before it can be touched again.
      if @hot_issues[issue_id][:status] == :hot
        @hot_issues[issue_id].merge!({
          status: :lukewarm,
          neighbor_batch_finished_at: now
        })
      end

      if has_cooled_down?(issue_id)
        cooled_issues << issue_id
      end
    end

    cooled_issues.each do |issue_id|
      @hot_issues.delete(issue_id)
    end
  end

  def is_cold?(issue_id)
    !@hot_issues.has_key?(issue_id) or has_cooled_down?(issue_id)
  end

  # if an issue was lukewarm, and enough time had passed, then it can be considered
  # cold, and can be transferred.
  def has_cooled_down?(issue_id)
    @hot_issues[issue_id][:status] == :lukewarm and @hot_issues[issue_id][:neighbor_batch_finished_at] <= Time.now - max_replication_lag
  end

  def mark_neighbors_as_hot(issue_id)
    return unless graph.neighbors?(issue_id)

    # mark all neighbors as hot in order to prevent transferring them at the same time.
    graph.neighbors(issue_id).each do |neighbor_id|
      mark_neighbor_as_hot(neighbor_id)
    end

    # mark the referenced neighbors of the referencing neighbors as hot.
    # More info here: https://github.com/github/issues/issues/2492#issuecomment-1078037679
    graph.referencing_neighbors(issue_id).each do |referencing_neighbor_id|
      graph.referenced_neighbors(referencing_neighbor_id).each do |referenced_neighbor_id|
        mark_neighbor_as_hot(referenced_neighbor_id)
      end
    end
  end

  def mark_neighbor_as_hot(neighbor_id)
    @hot_issues[neighbor_id][:status] = :hot
  end

  private

  def process_transfers_in_batches!
    batch_number = 1

    while !finished?
      batch = create_batch

      if batch.empty? && !finished?
        Rails.logger.info "Batch ##{batch_number} is empty. Waiting (sleep) for some issues to cool down..."
        sleep(max_replication_lag)
        next
      end

      Rails.logger.info "Processing batch ##{batch_number} containing #{batch.size} issues ..."

      time_batch(batch, batch_number) do
        transfer_issue_batch(batch)
        complete_batch(batch)
      end

      log_progress

      batch_number += 1
    end
  end

  def time_batch(batch, batch_number, &block)
    batch_timer = Timer.start

    block.call

    elapsed_seconds = batch_timer.elapsed_ms.to_f / 1000
    avg_per_issue = elapsed_seconds / batch.size
    Rails.logger.info "Batch ##{batch_number} done in #{elapsed_seconds} seconds (~#{avg_per_issue} seconds per issue)."
  end

  def log_progress
    Rails.logger.info "Progress is #{completed.size} of #{graph.ids.size} issues (#{(completed.size / graph.ids.size.to_f * 100).to_i}%)."
  end

  def create_all_transfers!
    Rails.logger.info "Creating transfers and initial copies for #{@graph.ids.size} issues ..."

    log_time "creating transfers" do
      issue_ids_to_transfer.each_slice(batch_size) do |batched_issue_ids|
        existing_transfer_issue_ids = IssueTransfer.where(old_issue_id: batched_issue_ids).pluck(:old_issue_id)
        issues_batch = Issue.where(id: batched_issue_ids - existing_transfer_issue_ids)

        Rails.logger.info "Creating transfers for issues #{issues_batch.first&.number}..#{issues_batch.last&.number} ..."

        issues_batch.map do |issue_to_transfer|
          Issue.throttle_with_retry(max_retry_count: @settings[:max_throttle_retries]) do
            issue_transfer = IssueTransfer.new(
              old_issue: issue_to_transfer,
              old_repository: old_repository,
              new_repository: new_repository,
              actor: actor
            )

            issue_transfer.create_empty_copy_issue
            issue_transfer.save!
          end
        end
      end
    end
  end

  def copy_issue_bodies!
    Rails.logger.info "Copying issue bodies for #{@graph.ids.size} issues ..."

    log_time "copying issues" do
      issue_ids_to_transfer.each_slice(batch_size) do |batched_issue_ids|
        new_issue_batch_ids = IssueTransfer.where(old_issue_id: batched_issue_ids).pluck(:new_issue_id)
        existing_bodies = Issue.where(id: new_issue_batch_ids).where.not(body: nil?).pluck(:id)
        issue_transfer_batch = IssueTransfer.where(old_issue_id: batched_issue_ids)
                                            .where.not(new_issue_id: existing_bodies)
                                            .preload(:new_issue, :old_issue)

        Rails.logger.info "Copying issue bodies for issues #{issue_transfer_batch.first&.old_issue&.number}..#{issue_transfer_batch.last&.old_issue&.number} ..."

        issue_transfer_batch.map do |transfer|
          Issue.throttle_with_retry(max_retry_count: @settings[:max_throttle_retries]) do
            T.must(transfer.new_issue).body = transfer.replace_body_mentions(T.must(transfer.old_issue).body.dup)
            T.must(transfer.new_issue).save!
          end
        end
      end
    end
  end

  def issue_ids_to_transfer
    @issue_ids_to_transfer ||= old_repository.issues.without_pull_requests.order(created_at: :asc).pluck(:id)
  end

  def log_time(message, &block)
    timer = Timer.start
    block.call
    timer.stop
    Rails.logger.info "Done #{message} in #{timer.elapsed_ms.to_f / 1000} seconds"
  end

  def transfer_issue_batch(batch)
    Rails.logger.info "Posting #{batch.size} transfers to queue with #{concurrent_jobs_count} concurrent jobs"

    while !batch.finished?
      if batch.can_enqueue_more?
        batch.enqueue_next_transfer
      end

      while batch.queue_full?
        Rails.logger.info "Queue is full with #{batch.active_transfers.size} jobs. Waiting..."
        sleep(1)
      end
    end

    Rails.logger.info "Waiting for all batch transfers to finish"

    while batch.has_active_transfers?
      Rails.logger.info "#{batch.active_transfers.size} transfers are still in progress. Waiting..."
      sleep(1)
    end

    Rails.logger.info "Batch execution finished"
  end
end
