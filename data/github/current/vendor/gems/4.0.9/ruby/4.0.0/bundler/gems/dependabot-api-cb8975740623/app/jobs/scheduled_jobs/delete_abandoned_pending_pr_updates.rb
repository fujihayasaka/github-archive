# frozen_string_literal: true

# Run in production once every minute, deleting up to 1000 rows.
#
# This job looks for old pending pull request updates that are older than 2 weeks
# and delete them, up to 1000 rows. We keep pending PR updates around for up to
# 2 weeks to give us some time to investigate if something goes wrong.
#
# This job deletes pending PR updates and all their dependent data from the DB, including
# attachment and blob records in `active_storage_*` DB tables.  This job does not purge
# any blobs from the storage service, where we expect the storage service to have already
# purged blobs before this 2 week retention period is up.
module ScheduledJobs
  class DeleteAbandonedPendingPrUpdates < ApplicationScheduledJob
    queue_as :default
    schedule interval: 1.minute

    def perform(limit: 1000)
      # We do not want to call `find_each` on this query, it tacks on an ORDER
      # BY to the query, and this grinds it to a halt when the dataset is large
      # enough. Since we're defaulting to 1000 records, loading them all into
      # memory should be fine.

      # Get the records to delete from read replica, but delete from primary
      records_to_delete = ActiveRecord::Base.connected_to(role: :reading) do
        pending_pr_updates_for_deletion.limit(limit).pluck(:id)
      end

      # Delete from primary database
      PendingPullRequestUpdate.transaction do
        PendingPullRequestUpdate.where(id: records_to_delete).delete_all_with_dependents
      end

      # Get the backlog count from read replica
      pending_pr_updates_backlog = ActiveRecord::Base.connected_to(role: :reading) do
        pending_pr_updates_for_deletion.count
      end

      Rails.logger.info(
        "Abandoned Pending PR Updates remaining: '#{pending_pr_updates_backlog}'.",
      )

      MetricsClient.gauge("scheduled_jobs.delete_abandoned_pending_pr_updates.backlog",
                          pending_pr_updates_backlog)
    end

    private

    def pending_pr_updates_for_deletion
      PendingPullRequestUpdate.where(created_at: ...2.weeks.ago)
    end
  end
end
