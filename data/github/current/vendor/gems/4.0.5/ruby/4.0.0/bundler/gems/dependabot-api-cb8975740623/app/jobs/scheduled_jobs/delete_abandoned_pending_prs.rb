# frozen_string_literal: true

# Run in production once every minute, deleting up to 2000 rows.
#
# This job looks for old pending pull requests that are older than 2 weeks
# and delete them, up to 2000 rows. We keep pending PRs around for up to
# 2 weeks to give us some time to investigate if something goes wrong.
#
# This job deletes pending PRs and all their dependent data from the DB, including
# attachment and blob records in `active_storage_*` DB tables.  This job does not purge
# any blobs from the storage service, where we expect the storage service to have already
# purged blobs before this 2 week retention period is up.
module ScheduledJobs
  class DeleteAbandonedPendingPrs < ApplicationScheduledJob
    queue_as :default
    schedule interval: 1.minute

    def perform(limit: 2000)
      # We do not want to call `find_each` on this query, it tacks on an ORDER
      # BY to the query, and this grinds it to a halt when the dataset is large
      # enough. Since we're defaulting to 2000 records, loading them all into
      # memory should be fine.

      ids_to_delete = ActiveRecord::Base.connected_to(role: :reading) do
        pending_prs_for_deletion.limit(limit).pluck(:id)
      end

      PendingPullRequest.transaction do
        PendingPullRequest.where(id: ids_to_delete).delete_all_with_dependents
      end

      pending_prs_for_deletion_backlog = ActiveRecord::Base.connected_to(role: :reading) do
        pending_prs_for_deletion.count
      end

      Rails.logger.info(
        "Abandoned Pending PRs remaining: '#{pending_prs_for_deletion_backlog}'.",
      )

      MetricsClient.gauge("scheduled_jobs.delete_abandoned_pending_prs.backlog",
                          pending_prs_for_deletion_backlog)
    end

    private

    def pending_prs_for_deletion
      PendingPullRequest.where(created_at: ...2.weeks.ago)
    end
  end
end
