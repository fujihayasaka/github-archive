# typed: true
# frozen_string_literal: true

class RecoverNotificationSummaryJob < ApplicationJob
  # This interface helps clients of the Metric class define their own
  # set of tags based on a result without exposing the exact operation they are doing
  # or the exact type of results they return
  module Taggable
    extend T::Helpers

    interface!

    sig { abstract.returns(T::Array[String]) }
    def tags; end
  end

  class BatchResult
    include Taggable

    def initialize(scope)
      @scope = scope
    end

    sig { override.returns(T::Array[String]) }
    def tags
      ["status:success", "scope:#{@scope}"]
    end
  end

  class Metric
    attr_reader :operation, :target

    def self.increment(operation:, target: "notification_summaries", &block)
      metric = new(operation: operation, target: target)

      begin
        if block.arity == 1
          yield(metric)
        else
          yield.tap { |result| metric.increment(result) }
        end
      rescue => err # rubocop:disable Lint/RescueException # The error is reraised, we just need to track it
        metric.error(err)

        raise err
      end
    end

    def initialize(operation:, target: "notification_summaries")
      @operation = operation
      @target = target
    end

    def increment(result)
      GitHub.dogstats.increment(name, tags: tags(result))
    end

    def count(count, result)
      GitHub.dogstats.count(name, count, tags: tags(result))
    end

    def error(err)
      GitHub.dogstats.increment(name, tags: [
        target_tag,
        "status:failure",
        "reason:#{err.class.name}",
      ])
    end

    private

    def name
      @name ||= "notifications.dual_summary.#{operation}"
    end

    def tags(result)
      tags = case result
      when Taggable
        result.tags
      when result
        ["status:success"]
      else
        ["status:failure", "unknown"]
      end

      tags + [target_tag]
    end

    def target_tag
      @target_tag ||= "target:#{target}"
    end
  end

  BATCH_SIZE = 100
  ENTRY_SCOPES = [
    Newsies::NotificationEntry,
    Newsies::SavedNotificationEntry,
  ]
  UNRECOVERABLE_ERRORS = [
    # Some commit references might not exist anymore
    GitRPC::ObjectMissing,
    # This is thrown by Sorbet in some paths where nil is used
    # nil values are references that don't exist anymore, like Orgs
    TypeError,
    # This is thrown in some codepaths when nil is used
    # nil values are references that don't exist anymore, like Orgs
    NoMethodError,
  ]

  # We can reuse the existing maintenance queue for this
  queue_as :notifications_maintenance

  locked_by key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC, timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT

  retry_on_dirty_exit
  retry_on_recoverable_exceptions

  # This job recovers missing notification summaries
  # so it doesn't need tenant context information
  exempt_from_tenant_context_requirement

  def perform(id:, list_type:, list_id:, thread_type:, thread_id:)
    list = Newsies::List.new(list_type, list_id)
    thread = Newsies::Thread.new(thread_type, thread_id, list: list)

    NotificationSummary.throttle do
      return if NotificationSummary.find_by(id: id)

      summary = NotificationSummary.by_thread(list, thread)
      if summary
        fix_references(old_id: id, new_id: summary.id, list: list, thread: thread)
      else
        recreate_summary(id: id, list: list, thread: thread)
      end
    end
  end

  def fix_references(old_id:, new_id:, list:, thread:)
    Metric.increment(operation: :fix_references) do |metric|
      ENTRY_SCOPES.each do |scope|
        result = BatchResult.new(scope.name)
        scope.for_list(list).for_thread(thread).where(summary_id: old_id).in_batches(of: BATCH_SIZE) do |batch|
          scope.throttle do
            with_write do
              count = batch.update_all(summary_id: new_id)
              metric.count(count, result)
            end
          end
        end
      end
    end
  end

  def recreate_summary(id:, list:, thread:)
    Metric.increment(operation: :recover) do
      summary = NotificationSummary.new(list: list, thread: thread)
      # By setting the ID, we make sure ActiveRecord uses it when saving
      summary.id = id
      summary.rebuild_summary(save_record: false)

      with_write do
        summary.save!
      end
    rescue *UNRECOVERABLE_ERRORS => error
      delete_unrecoverable_entries(id: id, list: list, thread: thread)
    end
  end

  def delete_unrecoverable_entries(id:, list:, thread:)
    Metric.increment(operation: :delete_unrecoverable_entries) do |metric|
      ENTRY_SCOPES.each do |scope|
        result = BatchResult.new(scope.name)
        scope.for_list(list).for_thread(thread).where(summary_id: id).in_batches(of: BATCH_SIZE) do |batch|
          scope.throttle do
            with_write do
              metric.count(batch.count(:id), result)
              batch.delete_all
            end
          end
        end
      end
    end
  end
end
