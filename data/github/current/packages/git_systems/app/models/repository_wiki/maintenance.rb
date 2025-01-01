# typed: false
# frozen_string_literal: true

class RepositoryWiki
  module Maintenance
    extend ActiveSupport::Concern

    RETRYABLE_ERRORS = [
      GitRPC::RepositoryOffline,
      GitRPC::NetworkError,
      GitRPC::Util::RepackLocked,

      # Various database/network errors.
      ActiveRecord::ConnectionFailed,
      ActiveRecord::ConnectionNotEstablished,
      ActiveRecord::StatementInvalid,
      ActiveRecord::QueryCanceled,
      SystemCallError, # Errno::ECONNREFUSED, Errno::ECONNRESET and friends
    ]

    class_methods do
      # Schedule maintenance tasks to run from the old and active generations. We
      # first find the wikis that have received the most pushes over the
      # maintenance threshold and then select the remaining number of records up to
      # the limit from the list of all wikis.
      #
      # limit          - Total number of wikis to schedule for maintenance.
      #
      # Returns an array of wikis that were scheduled.
      def schedule_maintenance(limit, min_age = 1.week)
        wikis  = find_most_active_since_last_maintenance(limit / 2, 50)
        wikis += find_longest_time_since_last_maintenance(limit - wikis.size, min_age)
        wikis += find_stale_failed_and_running_wikis(10, min_age)

        scheduled = wikis.uniq.each { |wiki| wiki.schedule_maintenance }

        RepositoryNetwork.move_stuck_networks_to_retry!(RepositoryWiki)
        scheduled
      end

      # Find wikis that are most in need of maintenance due to push/write activity.
      #
      # limit     - Maximum number of wikis to return.
      # threshold - Minimum number of pushes the wiki must have received to
      #             qualify for maintenance. Wikis that haven't received this
      #             many pushes since the last maintenance are not included.
      #
      # Returns an array of RepositoryWiki objects.
      def find_most_active_since_last_maintenance(limit, threshold = 50)
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            threshold: threshold,
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
            FROM repository_wikis
            WHERE maintenance_status IN ('complete', 'retry')
            AND (pushed_count_since_maintenance > :threshold)
            ORDER BY pushed_count_since_maintenance DESC
            LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end

      # Find wikis that require maintenance and have gone the longest without
      # receiving any. This includes wikis that have never had maintenance.
      # Wikis are selected ordered by last_maintenance_at, so
      # new and never visited wikis fall into the same time queue.
      #
      # limit      - Maximum number of wikis to return.
      # min_age    - Minimum length of time between maintenance runs for any single
      #              wiki in seconds. Wikis that have received maintenance
      #              within this limit will not be selected.
      #
      # Returns an array of RepositoryWiki objects.
      def find_longest_time_since_last_maintenance(limit, min_age = 1.week)
        time_cutoff = (Time.now - min_age)
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            cutoff: time_cutoff,
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
            FROM repository_wikis
            WHERE maintenance_status IN ('complete', 'retry')
            AND pushed_count_since_maintenance > 0
            AND last_maintenance_at < :cutoff
            ORDER BY last_maintenance_at ASC
            LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end

      # Find wikis whose
      #   * state is 'running' or 'failed'
      #   * last attempted maintenance was _age_ ago OR is NULL
      #   * ordered by pushes since last maintenance
      #
      # This is mainly important for GitHub Enterprise where chances are bigger that
      # jobs either get lost in 'running' due to hard crashes or have spurious failures
      # due to timeouts or OOM kills
      #
      def find_stale_failed_and_running_wikis(limit, age)
        cutoff = Time.now - age
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            cutoff: cutoff,
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
              FROM repository_wikis
             WHERE maintenance_status IN ('failed', 'running')
               AND pushed_count_since_maintenance > 0
               AND (last_maintenance_attempted_at < :cutoff OR last_maintenance_attempted_at IS NULL)
             ORDER BY last_maintenance_attempted_at ASC
             LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end
    end

    # Schedule maintenance for this wiki. This enqueues the job on
    # the fs maintenance queue and updates the maintenance status column.
    def schedule_maintenance
      return unless repository
      maintenance_queue_name.map do |queue_name|
        update_status :scheduled, last_maintenance_attempted_at: Time.now
        WikiMaintenanceJob.set(queue: queue_name).perform_later(id)
      end
    end

    def mark_as_broken
      update_status :broken
    end

    # Run maintenance on this wiki. This typically isn't called directly but
    # run from the WikiNetworkMaintenance job.
    def perform_maintenance
      started_at = Time.now
      pushed_count_at_start = pushed_count
      update_status :running

      unsullied_wiki.repack if unsullied_wiki.exist?

      # reload to get latest pushed_count and update status
      reload
      update_status :complete,
        last_maintenance_at: started_at,
        pushed_count_since_maintenance: (pushed_count - pushed_count_at_start)

    rescue *RETRYABLE_ERRORS => e
      update_status :retry, last_maintenance_at: started_at
      GitHub.logger.error("temporary error, trying again later", e)
    rescue => boom # rubocop:todo Lint/RescueException
      update_status :failed
      raise boom
    end

    # Find all repositories in the network that were modified since the last
    # time maintenance was performed. If maintenance has never been performed
    # for the network, all repositories are returned.
    def wikis_modified_since_last_maintenance
      conditions = nil
      conditions = ["pushed_at >= ?", last_maintenance_at] if last_maintenance_at
      where(conditions).order(:id).to_a
    end

    # Internal: Update the wiki record's maintenance_status in the database.
    #
    # value - One of the maintenance status values as a string.
    #
    # Returns nothing.
    def update_status(value, attributes = {})
      attributes = attributes.merge(maintenance_status: value.to_s)
      update!(attributes)
    end

    # Internal: The queue where maintenance jobs should be scheduled
    # for this wiki.
    def maintenance_queue_name
      repository.maintenance_queue_name
    end
  end
end
