# typed: true
# frozen_string_literal: true

class CodespacesCheckForHungAsyncOperationsJob < CodespacesJob
  locked_by timeout: 1.minute, key: DEFAULT_LOCK_PROC
  schedule interval: 5.minutes, condition: -> { !GitHub.enterprise? }

  retry_on_dirty_exit

  def perform
    hung_ops_count = Hash.new(0)
    hung_ops = Codespaces::AsyncOperation.hung_operations.each do |op|
      CodespacesAsyncOperationTimeoutJob.perform_later(op)
      hung_ops_count[op.operation] += 1
    end

    ongoing_ops_count = Hash.new(0)
    ongoing_ops = Codespaces::AsyncOperation.ongoing_operations - hung_ops
    ongoing_ops.each do |op|
      CodespacesAsyncOperationSyncStateJob.perform_later(op)
      ongoing_ops_count[op.operation] += 1
    end

    unstarted_ops_count = Hash.new(0)
    Codespaces::AsyncOperation.unstarted_operations.each do |op|
      CodespacesAsyncOperationTimeoutJob.perform_later(op)
      unstarted_ops_count[op.operation] += 1
    end

    hung_ops_count.each do |op, count|
      GitHub.dogstats.count("codespaces.async_operations.hung_jobs", count, tags: ["operation:#{op}"])
    end

    ongoing_ops_count.each do |op, count|
      GitHub.dogstats.count("codespaces.async_operations.ongoing_jobs", count, tags: ["operation:#{op}"])
    end

    unstarted_ops_count.each do |op, count|
      GitHub.dogstats.count("codespaces.async_operations.unstarted_jobs", count, tags: ["operation:#{op}"])
    end
  end
end
