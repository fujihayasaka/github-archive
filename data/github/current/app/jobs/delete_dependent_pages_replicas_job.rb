# typed: false
# frozen_string_literal: true

# DeleteDependentPagesReplicasJob deletes all pages_replicas for a fileserver when it's removed.
# This is triggered presently by running `script/dpages remove <fileserver_hostname>`.
class DeleteDependentPagesReplicasJob < ApplicationJob
  queue_as :background_destroy

  # In order to reduce the likelihood that these deletions cause replication lag,
  # we need to delete in very small batches. A large deletion of 1000 or more rows
  # can cause the replicas to lag, so it's best to delete in small batches and throttle.
  BATCH_SIZE = 100

  def perform(pages_fileserver_hostname, *args)
    @pages_fileserver_hostname = pages_fileserver_hostname

    Failbot.push(
        :app => "pages",
        "gh.pages.fileserver.hostname" => pages_fileserver_hostname)

    rows_deleted = 0
    loop do
      affected_rows = 0

      Page::Replica.throttle_writes do
        affected_rows = Page::Replica.connection.delete(Arel.sql(<<~SQL, host: pages_fileserver_hostname, count: Arel.sql(BATCH_SIZE.to_s)))
          DELETE FROM pages_replicas WHERE host = :host LIMIT :count
        SQL

        rows_deleted += affected_rows
      end

      break if affected_rows == 0
    end

    GitHub.dogstats.distribution("delete_dependent_records.dist", rows_deleted, tags: all_stats_tags)
  end

  def stats_tags
    [
      "model:pages_replicas",
      "pages_fileserver_hostname:#{@pages_fileserver_hostname}",
    ]
  end

  retry_on_recoverable_exceptions
  retry_on_dirty_exit
end
