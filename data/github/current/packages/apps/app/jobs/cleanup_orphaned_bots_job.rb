# typed: true
# frozen_string_literal: true

# This job will remove all Bots without a corresponding GitHub App in the database.
class CleanupOrphanedBotsJob < ApplicationJob
  queue_as :cleanup_orphaned_bots
  retry_on_dirty_exit

  BATCH_SIZE = 1_000

  locked_by timeout: 5.minutes, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # This job is exempt from the tenant context requirement because it is
  #  used to clean up orphaned records regardless of the tenant.
  exempt_from_tenant_context_requirement

  def perform
    return unless enabled?

    orphaned_bots = []

    Bot.preload(:integration).find_in_batches(batch_size: BATCH_SIZE) do |bots|
      bots.each do |bot|
        orphaned_bots << bot if bot.integration.nil?
      end
    end

    if destroy_enabled?
      with_write do
        Bot.throttle do
          orphaned_bots.each(&:destroy)
        end
      end
    end

    report_result(orphaned_bots)
  end

  private

  def enabled?
    GitHub.enterprise? || GitHub.flipper[:cleanup_orphaned_bots].enabled?
  end

  def destroy_enabled?
    GitHub.enterprise? || GitHub.flipper[:cleanup_orphaned_bots_destroy].enabled?
  end

  def report_result(orphaned_bots)
    destroyed_orphaned_bots = orphaned_bots.select(&:destroyed?)
    all_removed = destroyed_orphaned_bots.size == orphaned_bots.size

    GitHub.dogstats.distribution(
      "cleanup_orphaned_bots_job.orphaned_bots",
      orphaned_bots.size,
      tags: ["all_removed:#{all_removed}"],
    )

    GitHub.logger.info(
      {
        "gh.job.name" => "CleanupOrphanedBotsJob",
        "identified_orphaned_bot_ids" => orphaned_bots.map(&:id),
        "removed_orphaned_bot_ids" => destroyed_orphaned_bots.map(&:id),
      }
    )
  end
end
