# typed: false
# frozen_string_literal: true

module Gist::Maintenance
  extend ActiveSupport::Concern

  MAINTENANCE_STATUSES = %w[scheduled running complete failed retry broken]

  # The amount of time we wait after a network has seen a spurious failure
  # before we retry maintenance
  SPURIOUS_FAILURE_WAIT_TIME = 1.hour

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

  module ClassMethods
    # Schedule maintenance tasks to run from the old and active generations. We
    # first find the gists that have received the most pushes over the
    # maintenance threshold and then select the remaining number of records up to
    # the limit from the list of all gists.
    #
    # limit          - Total number of gists to schedule for maintenance.
    #
    # Returns an array of gists that were scheduled.
    def schedule_maintenance(limit, min_age = 1.week)
      gists = find_most_active_since_last_maintenance(limit / 2, 50)
      most_active_count = gists.size
      gists += find_longest_time_since_last_maintenance(limit - gists.size, min_age)
      gists += find_stale_failed_and_running_gists(10, min_age)
      gists += find_spurious_failure_gists(10, SPURIOUS_FAILURE_WAIT_TIME)
      longest_time_count = gists.size - most_active_count
      GitHub.dogstats.gauge("gist.maint.count", most_active_count, tags: ["type:most_active"])
      GitHub.dogstats.gauge("gist.maint.count", longest_time_count, tags: ["type:longest_time"])

      scheduled = GitHub.dogstats.time("gist.maint.time", tags: ["action:schedule_maintenance"]) do
        gists.uniq.each { |gist| gist.schedule_maintenance }
      end

      RepositoryNetwork.move_stuck_networks_to_retry!(Gist)
      scheduled
    end

    # Find gists that are most in need of maintenance due to push/write activity.
    #
    # limit     - Maximum number of gists to return.
    # threshold - Minimum number of pushes the gist must have received to
    #             qualify for maintenance. Gists that haven't received this
    #             many pushes since the last maintenance are not included.
    #
    # Returns an array of Gist objects.
    def find_most_active_since_last_maintenance(limit, threshold = 50)
      ActiveRecord::Base.connected_to(role: :reading) do
        sql_bindings = {
          threshold: threshold,
          limit: Arel.sql(limit.to_s),
        }
        sql = Arel.sql <<-SQL, **sql_bindings
          SELECT *
          FROM gists
          WHERE maintenance_status IN ('complete', 'retry')
          AND (pushed_count_since_maintenance > :threshold)
          ORDER BY pushed_count_since_maintenance DESC
          LIMIT :limit
        SQL
        self.find_by_sql(sql)
      end
    end

    # Find gists that require maintenance and have gone at least a while
    # without receiving any. This includes gists that have never had
    # maintenance.  New and never visited gists fall into the same time
    # queue.
    #
    # This query used to be ordered by last_maintenance_at -- favoring the
    # least-recently-maintained gists -- but that's expensive, and the
    # query was timing out.  In the steady state, we want all gists to
    # have recent maintenance, and the ordering won't matter.
    #
    # limit      - Maximum number of gists to return.
    # min_age    - Minimum length of time between maintenance runs for any single
    #              gist in seconds. Gists that have received maintenance
    #              within this limit will not be selected.
    #
    # Returns an array of Gist objects.
    def find_longest_time_since_last_maintenance(limit, min_age = 1.week)
      time_cutoff = (Time.now - min_age)
      ActiveRecord::Base.connected_to(role: :reading) do
        sql_bindings = {
          cutoff: time_cutoff,
          limit: Arel.sql(limit.to_s),
        }
        sql = Arel.sql <<-SQL, **sql_bindings
          SELECT *
          FROM gists
          FORCE INDEX (index_gists_on_maintenance_status)
          WHERE maintenance_status IN ('complete', 'retry')
          AND pushed_count_since_maintenance > 0
          AND last_maintenance_at < :cutoff
          LIMIT :limit
        SQL
        self.find_by_sql(sql)
      end
    end

    # Find gists whose
    #   * state is 'running' or 'failed'
    #   * last attempted maintenance was _age_ ago OR is NULL
    #   * ordered by pushes since last maintenance
    #
    # This is mainly important for GitHub Enterprise where chances are bigger that
    # jobs either get lost in 'running' due to hard crashes or have spurious failures
    # due to timeouts or OOM kills
    #
    def find_stale_failed_and_running_gists(limit, age)
      cutoff = Time.now - age
      ActiveRecord::Base.connected_to(role: :reading) do
        sql_bindings = {
          cutoff: cutoff,
          limit: Arel.sql(limit.to_s),
        }
        sql = Arel.sql <<-SQL, **sql_bindings
        SELECT *
          FROM gists
         WHERE maintenance_status IN ('failed', 'running')
           AND pushed_count_since_maintenance > 0
           AND (last_maintenance_attempted_at < :cutoff OR last_maintenance_attempted_at IS NULL)
         ORDER BY last_maintenance_attempted_at ASC
         LIMIT :limit
        SQL
        self.find_by_sql(sql)
      end
    end

    # Find gists whose
    #   * state is 'spurious_failure'
    #   * last attempted maintenance was _age_ ago OR is NULL
    #   * ordered by pushes since last maintenance
    #
    def find_spurious_failure_gists(limit, age)
      cutoff = Time.now - age
      ActiveRecord::Base.connected_to(role: :reading) do
        sql_bindings = {
          cutoff: cutoff,
          limit: Arel.sql(limit.to_s),
        }
        sql = Arel.sql <<-SQL, **sql_bindings
        SELECT *
          FROM gists
         WHERE maintenance_status = 'spurious_failure'
           AND pushed_count_since_maintenance > 0
           AND (last_maintenance_attempted_at < :cutoff OR last_maintenance_attempted_at IS NULL)
         ORDER BY last_maintenance_attempted_at ASC
         LIMIT :limit
        SQL
        self.find_by_sql(sql)
      end
    end

    def maintenance_counts
      # "complete" is the normal, most populated state. The remaining states are
      # the only ones we're interested in.
      metric_statuses = MAINTENANCE_STATUSES.reject { |s| s == "complete" }

      # We want zero-value defaults so our caller can emit the proper 0s.
      counts = Hash.new
      metric_statuses.each do |s|
        counts[s] = 0
      end

      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql <<-SQL, statuses: metric_statuses
          SELECT maintenance_status, COUNT(*)
            FROM gists
          WHERE maintenance_status IN (:statuses)
          GROUP BY maintenance_status
        SQL

        Gist.connection.select_rows(sql).each do |s, c|
          counts[s] = c
        end

        counts
      end
    end

  end

  # Schedule maintenance for this gist. This enqueues the job on
  # the fs maintenance queue and updates the maintenance status column.
  def schedule_maintenance
    # Don't schedule gists that can't have maint ran on them
    return if maintenance_disabled?

    maintenance_queue_name.map do |queue_name|
      previous_status = maintenance_status
      update_status :scheduled, last_maintenance_attempted_at: Time.now
      GistMaintenanceJob.set(queue: queue_name).perform_later(id, previous_status: previous_status)
    end
  end

  # Are maint operations disabled on this Gist?
  #
  # If this is gist is already marked as maint status broken, return true.
  # If git-backup-ctl has marked this gist repo as not able to be
  # backed up, return true.
  def maintenance_disabled?
    return true if maintenance_status.to_s == "broken"

    if backups_disabled_by_backup_ctl?
      return true
    end

    false
  end

  def mark_as_broken
    update_status :broken
  end

  # Run maintenance on this gist. This typically isn't called directly but
  # run from the GistMaintenance job.
  def perform_maintenance(previous_status = :scheduled)
    # Don't perform maint on gists that can't have maint ran on them
    return if maintenance_disabled?

    started_at = Time.now
    pushed_count_at_start = pushed_count
    update_status :running

    repack if exists_on_disk?

    # reload to get latest pushed_count and update status
    reload
    update_status :complete,
      last_maintenance_at: started_at,
      pushed_count_since_maintenance: (pushed_count - pushed_count_at_start)

  rescue *RETRYABLE_ERRORS => e
    update_status :retry, last_maintenance_at: started_at
    GitHub.logger.error("temporary error, trying again later", e)
  rescue # rubocop:todo Lint/RescueException
    case check_gist
    when :fixed
      GitHub.logger.error("gist had corruption, which was fixed")
      GitHub.dogstats.increment("git_maintenance.corruption", tags: ["type:gist", "result:fixed"])
      update_status(:retry)
      return
    when :corrupt
      GitHub.logger.error("gist is corrupt")
      GitHub.dogstats.increment("git_maintenance.corruption", tags: ["type:gist", "result:corrupted"])
    end

    if previous_status == "spurious_failure" && maintenance_retries >= 3
      update_status(:failed, maintenance_retries: 0)
    else
      status = previous_status == "failed" ? :failed : :spurious_failure
      if previous_status != "failed" && previous_status != "spurious_failure"
        retries = 0
      else
        retries = maintenance_retries + 1
      end
      update_status(status, maintenance_retries: retries)
    end

    raise
  end

  # Find all gists that were modified since the last
  # time maintenance was performed. If maintenance has never been performed,
  # all gists are returned.
  #
  # TODO: Since gists don't have networks, I doubt we want to return all gists here
  def gists_modified_since_last_maintenance
    conditions = nil
    conditions = ["pushed_at >= ?", last_maintenance_at] if last_maintenance_at
    ::Gist.where(conditions).order(:id).to_a
  end

  # Internal: Update the gist record's maintenance_status in the database.
  #
  # value - One of the maintenance status values as a string.
  #
  # Returns nothing.
  def update_status(value, attributes = {})
    attributes = attributes.merge(maintenance_status: value.to_s)

    # Push Gist#failbot_context into failbot context to help diagnose failing jobs
    Failbot.push failbot_context

    # Don't touch updated_at
    Gist.without_timestamps do
      update!(attributes)
    end
  end

  # Internal: The background job queue where maintenance jobs should be scheduled
  # for this gist.
  def maintenance_queue_name
    if !@dgit_maintenance_host
      all_replicas = GitHub::DGit::Routing.all_gist_replicas(id)
      replica = all_replicas.find(&:healthy?)
      if !replica
        # The gist is unrouted. Fall back on unhealthy or offline
        # replicas. (We're queueing a job; it can wait until the
        # chosen replica comes back.)
        replica = all_replicas.find { |replica| replica.checksum_ok? && replica.online? } ||
                  all_replicas.find { |replica| replica.checksum_ok? }
      end
      # FIXME: what if there is no replica at all?
      @dgit_maintenance_host = replica && replica.host
    end
    if @dgit_maintenance_host
      GitHub::Result.new { "maint_#{@dgit_maintenance_host}" }
    else
      GitHub::Result.error("no replicas available")
    end
  end

  # Update the disk_usage attribute in the database
  # Returns the newly recorded disk usage value in kilobytes.
  def update_disk_usage
    disk_usage = exists_on_disk? && rpc.repo_disk_usage
    disk_usage = (disk_usage || 0) / 1024
    update_column :disk_usage, disk_usage
    disk_usage
  end

  def human_disk_usage
    if disk_usage < 1000
      "#{disk_usage}KB"
    else
      "#{"%.02f" % (disk_usage / 1000.0)}MB"
    end
  end

  # Internal: Optimize pack files in the gist repository. This
  # rebuilds all packs that have accumulated since the last maintenance into
  # a single optimized pack and builds bitmap indexes. No objects are pruned
  # during the repack so this method can be used to safely optimize pack
  # storage without any risk of repository corruption.
  #
  # Returns nothing.
  def repack
    GitRPC::Util.with_repack_error_handler do
      rpc.nw_repack
    end
    nil
  end

  def check_gist
    if corrupt?
      begin
        res = rpc.restore_objects(max: 10000)
        return :corrupt if !res["ok"]
        :fixed if res["err"] =~ /object was restored/ || res["err"] =~ /objects were restored/
      rescue GitRPC::Protocol::DGit::ResponseError
        :corrupt
      end
    end
  end

  def corrupt?
    begin
      res = rpc.nw_fsck
      !res["ok"]
    rescue GitRPC::Protocol::DGit::ResponseError
      true
    end
  end
end
