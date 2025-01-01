# typed: false
# frozen_string_literal: true

require "set"
require "github/slice_query"

# Repository Network Maintenance
#
# Logic for scheduling and performing maintenance tasks like running git-gc,
# measuring disk usage, or running health checks on whole repository networks.
#
# == Maintenance required
#
# Git repositories accumulate new data in the form of pack files, loose objects,
# and refs. Each time a repository is pushed to, it results in a new pack file
# containing the git objects and a set of ref changes. Over time, performance
# suffers as packs and ref changes pile up in this unoptimized form. The
# maintenance tasks run git-gc to optimize the layout of these files.
#
# It's also useful to measure usage information about a network or repositories
# that have changed after maintenance is performed.
#
# == Scheduling
#
# Maintenance jobs for individual networks are scheduled at a regular interval
# by a timerd task. It looks at all networks and decides which are most in need
# of maintenance. The networks scheduled come from two different views of the
# repository_networks table:
#
# - Active generation. Networks that received a significant amount of push/write
#   activity since maintenance was last performed. This is to pro actively optimize
#   networks that are highly write active and stored inefficiently.
#
# - Old generation. The set of all networks ordered by when maintenance was last
#   performed, least recently to most recently. This is to guarantee that all
#   networks eventually receive maintenance.
#
# Each time timerd fires, networks are scheduled from each generation.
class RepositoryNetwork
  module Maintenance
    extend ActiveSupport::Concern

    included do
      include SliceQuery

      # The maintenance_status attribute is used to track maintenance job runs.
      # Possible values are:
      #
      # scheduled        - maintenance job has been scheduled but is not yet running.
      # running          - maintenance job is running on a worker.
      # complete         - maintenance job completed successfully.
      # failed           - maintenance job failed.
      # spurious_failure - maintenance job failed in an unknown way, but we'll retry
      #                    it once more before giving up.
      # retry            - maintenance job failed because of an error that we deem
      #                    recoverable, so we can retry it
      # broken           - the repository network is broken and cannot be recovered,
      #                    so further maintenance jobs should not be attempted
      #
      # May also be nil, in which case maintenance has never been performed for the
      # repository network.
      validates_inclusion_of :maintenance_status,
        in: MAINTENANCE_STATUSES,
        allow_nil: true
    end

    MAINTENANCE_STATUSES = %w[scheduled running complete failed spurious_failure retry broken]

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

    # If a network has been :scheduled for longer than this, it's stale.
    # That is, the job was lost, or the DB update at the end of the job was
    # lost.  Treat it as retryable.
    SCHEDULED_STALE_TIME = 3.hours

    # If a network is in the retry state and has not run maintenance for longer
    # than this, check to see if it's missing a root.
    RETRY_STALE_TIME = 3.hours

    # The amount of time we wait after a network has seen a spurious failure
    # before we retry maintenance
    SPURIOUS_FAILURE_WAIT_TIME = 1.hour

    # Number of geometric repacks to run between full repacks.
    FULL_REPACK_THRESHOLD = 32

    # Number of pushes before we consider a repo in need of maintenance.
    PUSH_THRESHOLD = 50

    # Size of unpacked pushes (in mb) before we consider a repo in need of maintenance.
    SIZE_THRESHOLD = 40

    class_methods do
      # Given an Array of networks, return the subset which haven't been
      # moved to or from cold storage within the last two hours.
      def filter_recently_frozen_and_thawed(networks)
        candidate_network_ids_set = Set.new(networks.uniq.map { |network| network.id })
        unless candidate_network_ids_set.empty?
          GitHub::DGit::DB.each_network_db do |db|
            sql = db.SQL.new \
              ids: candidate_network_ids_set.to_a,
              frozen_thaw_recency: 120
            sql.add <<-SQL
              SELECT network_id
                FROM cold_networks
               WHERE network_id in :ids
                 AND updated_at > NOW() - INTERVAL :frozen_thaw_recency MINUTE
            SQL
            candidate_network_ids_set -= Set.new(sql.results.flatten)
          end # each_network_db
        end
        networks.select { |network| candidate_network_ids_set.include?(network.id) }
      end

      # Schedule maintenance tasks to run from the old and active generations. We
      # first find the networks that have received the most pushes over the
      # maintenance threshold and then select the remaining number of records up to
      # the limit from the list of all networks.
      #
      # limit          - Total number of networks to schedule for maintenance.
      # host_threshold - Max number of maintenance jobs that can be scheduled for an
      #                  individual host. No jobs will be enqueued for hosts with more
      #                  networks scheduled.
      #
      # Returns an array of networks that were scheduled.
      def schedule_maintenance(limit, host_threshold = 1_000, min_age = 1.week)
        exclusions = scheduled_maintenance_exclusions(host_threshold)
        networks  = find_most_active_since_last_maintenance(limit, PUSH_THRESHOLD, SIZE_THRESHOLD, exclusions)
        networks += find_spurious_failure_networks(10, SPURIOUS_FAILURE_WAIT_TIME)
        networks += find_stale_failed_networks(10, 1.day)
        networks += find_stale_running_networks(10, 4.hours)

        networks = filter_recently_frozen_and_thawed(networks)

        scheduled = networks.uniq.each { |network| network.schedule_maintenance }

        move_orphaned_networks_to_broken!
        move_stuck_networks_to_retry!(RepositoryNetwork)
        scheduled
      end

      def find_failed_networks(limit = 10, order_by = :pushed_count)
        unless %w[pushed_count disk_usage pushed_count_since_maintenance unpacked_size_in_mb].include? order_by.to_s
          raise ArgumentError, "Invalid order-by value, #{order_by}"
        end

        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            order: Arel.sql(order_by.to_s),
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
              FROM repository_networks
             WHERE maintenance_status = 'failed'
             ORDER BY :order DESC
             LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end

      def find_spurious_failure_networks(limit = 10, age = 4.hours, order_by = :pushed_count_since_maintenance)
        unless %w[pushed_count disk_usage pushed_count_since_maintenance unpacked_size_in_mb].include? order_by.to_s
          raise ArgumentError, "Invalid order-by value, #{order_by}"
        end

        cutoff = Time.now - age
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            order: Arel.sql(order_by.to_s),
            cutoff: cutoff,
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
              FROM repository_networks
             WHERE maintenance_status = 'spurious_failure'
               AND pushed_count_since_maintenance > 0
               AND (last_maintenance_attempted_at < :cutoff OR last_maintenance_attempted_at IS NULL)
             ORDER BY :order DESC
             LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end

      # Find networks whose
      #   * state is 'failed'
      #   * last attempted maintenance was _age_ ago OR is NULL
      #   * ordered by pushes since last maintenance
      #
      # This is mainly important for GitHub Enterprise where chances are bigger that
      # jobs either get lost in 'running' due to hard crashes or have spurious failures
      # due to timeouts or OOM kills
      #
      def find_stale_failed_networks(limit, age)
        cutoff = Time.now - age
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            cutoff: cutoff,
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
              FROM repository_networks rn
             WHERE maintenance_status = 'failed'
               AND pushed_count_since_maintenance > 0
               AND (last_maintenance_attempted_at < :cutoff OR last_maintenance_attempted_at IS NULL)
             ORDER BY last_maintenance_attempted_at ASC
             LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end

      # Find networks whose
      #   * state is 'running'
      #   * last attempted maintenance was _age_ ago OR is NULL
      #   * ordered by pushes since last maintenance
      #
      # This is mainly important for GitHub Enterprise where chances are bigger that
      # jobs either get lost in 'running' due to hard crashes or have spurious failures
      # due to timeouts or OOM kills
      #
      def find_stale_running_networks(limit, age)
        cutoff = Time.now - age
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            cutoff: cutoff,
            limit: Arel.sql(limit.to_s),
          }
          sql = Arel.sql <<-SQL, **sql_bindings
            SELECT *
              FROM repository_networks rn
             WHERE maintenance_status = 'running'
               AND pushed_count_since_maintenance > 0
               AND (last_maintenance_attempted_at < :cutoff OR last_maintenance_attempted_at IS NULL)
             ORDER BY last_maintenance_attempted_at ASC
             LIMIT :limit
          SQL
          self.find_by_sql(sql)
        end
      end

      # Schedule a batch of maintenance runs on repositories where the Maintenance
      # job has previously failed. To prevent repeated repository jobs that would
      # always fail (i.e. on repositories that are completely botchered), we sort by
      # the amount of pushes to the network.
      #
      # Failed networks with a big amount of pushes have probably failed because
      # of one-off errors, such as failing to grab a lock or a network issue. These
      # should be retried until they run successfully.
      #
      # TODO: eventually, jobs that fail in non-recoverable ways will be marked
      # as 'disabled' and will never run again
      def schedule_maintenance_retries(limit = 10, order_by = :pushed_count)
        networks = find_failed_networks(limit, order_by)
        networks.each { |network| network.schedule_maintenance }
      end

      # Find networks that are most in need of maintenance due to push/write activity.
      #
      # limit     - Maximum number of networks to return.
      # count_threshold - Minimum number of pushes the network must have
      #                   received to qualify for maintenance.
      # size_threshold - Minimum size of unpacked pushes (in MB) the network
      #                  must have received to qualify for maintenance.
      # exclusions - an array of hosts too busy to perform maintenance.
      #
      # A network is eligible for maintenance if either count_threshold or
      # size_threshold is exceeded.
      #
      # Returns an array of RepositoryNetwork objects.
      def find_most_active_since_last_maintenance(limit, count_threshold, size_threshold, exclusions = nil)
        ActiveRecord::Base.connected_to(role: :reading) do
          sql_bindings = {
            count_threshold: count_threshold,
            limit: Arel.sql(limit.to_s)
          }
          sql = Arel.sql(<<-SQL, **sql_bindings)
            (
              SELECT *
                FROM repository_networks
               WHERE maintenance_status = 'complete'
                 AND pushed_count_since_maintenance > :count_threshold
               ORDER BY pushed_count_since_maintenance DESC
               LIMIT :limit
            )
           UNION ALL
            (
              SELECT *
                FROM repository_networks
               WHERE maintenance_status = 'retry'
                 AND pushed_count_since_maintenance > :count_threshold
               ORDER BY pushed_count_since_maintenance DESC
               LIMIT :limit
            )
          SQL
          candidates = RepositoryNetwork.find_by_sql(sql)

          sql_bindings = {
            size_threshold: size_threshold,
            limit: Arel.sql(limit.to_s)
          }
          sql = Arel.sql(<<-SQL, **sql_bindings)
            (
              SELECT *
                FROM repository_networks
               WHERE maintenance_status = 'complete'
                 AND unpacked_size_in_mb > :size_threshold
               ORDER BY unpacked_size_in_mb DESC
               LIMIT :limit
            )
           UNION ALL
            (
              SELECT *
                FROM repository_networks
               WHERE maintenance_status = 'retry'
                 AND unpacked_size_in_mb > :size_threshold
               ORDER BY unpacked_size_in_mb DESC
               LIMIT :limit
            )
            SQL
          candidates += RepositoryNetwork.find_by_sql(sql)

          fudge = count_threshold.to_f / size_threshold
          network_score = lambda do |rn|
            [rn.pushed_count_since_maintenance.to_i, fudge * rn.unpacked_size_in_mb.to_i].max
          end

          candidates = candidates.sort_by { |rn| -network_score.call(rn) }.uniq.first(limit)

          candidate_network_ids_set = candidates.map { |candidate| candidate.id }.to_set

          # Second filter out any network IDs that have corresponding
          # network_replica entries on hosts from the exclusion list.
          if exclusions && !candidate_network_ids_set.empty?
            GitHub::DGit::DB.each_network_db do |db|
              sql = db.SQL.new \
                candidate_network_ids: candidate_network_ids_set.to_a,
                hosts: exclusions
              sql.add <<-SQL
                  SELECT network_id
                    FROM network_replicas
                   WHERE network_id in :candidate_network_ids
                     AND host in :hosts
                SQL
              candidate_network_ids_set -= Set.new(sql.results.flatten)
            end # each_network_db
          end

          unless candidate_network_ids_set.empty?
            # Finally select full details for the remaining IDs to
            # instantiate the RepositoryNetwork results.
            sql = Arel.sql(<<-SQL, ids: candidate_network_ids_set.to_a)
                SELECT *
                  FROM repository_networks
                 WHERE id IN (:ids)
              SQL
            rows = self.find_by_sql(sql).sort_by { |rn| -network_score.call(rn) }
          end

          rows || []
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
              FROM repository_networks
             WHERE maintenance_status IN (:statuses)
            GROUP BY maintenance_status
          SQL

          RepositoryNetwork.connection.select_rows(sql).each do |s, c|
            counts[s] = c
          end

          counts
        end
      end

      def count_over_activity_threshold
        ActiveRecord::Base.connected_to(role: :reading) do
          sql = Arel.sql(<<-SQL, push_threshold: PUSH_THRESHOLD)
            SELECT COUNT(*)
              FROM repository_networks
             WHERE maintenance_status = "complete"
               AND pushed_count_since_maintenance > :push_threshold
          SQL

          count = RepositoryNetwork.connection.select_value(sql)

          sql = Arel.sql(<<-SQL, size_threshold: SIZE_THRESHOLD)
            SELECT COUNT(*)
              FROM repository_networks
             WHERE maintenance_status = "complete"
               AND unpacked_size_in_mb > :size_threshold
          SQL
          count += RepositoryNetwork.connection.select_value(sql)
          count
        end
      end

      # Internal: SQL conditions used to exclude networks from the maintenance scheduling
      # system dynamically. Excludes networks that live on hosts with large
      # maintenance backlogs.
      #
      # threshold - The maximim number of maintenance jobs that can be scheduled per host.
      #
      # Returns an array of hosts too busy to perform maintenance, or nil if
      # nothing should be excluded.
      def scheduled_maintenance_exclusions(threshold = 5_000)
        exclude_hosts = scheduled_maintenance_by_host.select { |_host, count| count >= threshold }.map(&:first)
        exclude_hosts if exclude_hosts.any?
      end

      # Determine the number of individual network maintenance jobs are scheduled on
      # each fs host. This is useful for backing off of scheduling hosts that have a
      # large backlog of networks to process.
      #
      # Returns a { "hostname" => count } hash. Only hosts that have at least one
      # scheduled maintenance job are included.
      def scheduled_maintenance_by_host
        rows = []
        dgit_scheduled = connection.select_rows("
          SELECT id
            FROM repository_networks
           WHERE maintenance_status = 'scheduled'
        ").flatten

        if dgit_scheduled.any?
          GitHub::DGit::DB.each_network_db do |db|
            rows += db.SQL.results(
              "SELECT host, COUNT(*) FROM network_replicas WHERE network_id IN :ids GROUP BY host",
              ids: dgit_scheduled)
          end # each_network_db
        end

        rows
      end

      # Move any network/gist/wiki which has been scheduled for longer than 'stale'
      # time to the retry status.
      #
      # We use the AR model instead of a table since all three kinds of repository
      # "network" have the same fields that we use here.
      #
      # klass - the AR model for your kind of repository
      # stale - the amount of time in scheduled state to be considered stale, defaults to SCHEDULED_STALE_TIME
      def move_stuck_networks_to_retry!(klass, stale = SCHEDULED_STALE_TIME)
        n = klass.
            where(maintenance_status: :scheduled).
            where("last_maintenance_attempted_at < ?", Time.now - stale).
            update_all(maintenance_status: :retry)

        # If we did move some networks
        if n > 0
          errmsg = "moved #{n} #{klass.to_s.downcase.pluralize} that were stuck as scheduled"
          Failbot.report(StandardError.new(errmsg), app: "github")
        end
        n
      end

      # Move networks which are in the retry status and stale but
      # have no repositories to the broken status.
      #
      # This can happen if a network gets scheduled and then gets partially
      # deleted.  In such a case, there's nothing to do unless it gets
      # resurrected and it isn't useful in its current state, so mark it as
      # broken.
      #
      # stale - the amount of time in scheduled state to be considered stale, defaults to RETRY_STALE_TIME
      def move_orphaned_networks_to_broken!(stale = RETRY_STALE_TIME)
        network_ids = ActiveRecord::Base.connected_to(role: :reading) do
          sql = Arel.sql(<<-SQL, time: Time.now - stale)
            SELECT rn.id, rn.maintenance_status, rn.root_id, rn.last_maintenance_attempted_at
              FROM repository_networks rn LEFT OUTER JOIN repositories r
                ON rn.id = r.source_id
             WHERE rn.maintenance_status = 'retry'
               AND rn.last_maintenance_attempted_at < :time
               AND r.source_id IS NULL
          SQL
          RepositoryNetwork.connection.select_rows(sql).map { |item| item.first }
        end

        n = RepositoryNetwork.where(id: network_ids).update_all(maintenance_status: :broken)

        # If we did move some networks
        if n > 0
          errmsg = "moved #{n} networks that were broken"
          Failbot.report(StandardError.new(errmsg), app: "github")
        end
        n
      end
    end

    # '#maintenance_pending?' returns whether or not maintenance is currently
    # pending.
    #
    # A repository has pending maintenance when either maintenance is currently
    # running, or is scheduled to run.
    #
    # Returns: Boolean.
    def maintenance_pending?
      maintenance_status == "scheduled" || maintenance_status == "running"
    end

    # Schedule maintenance for this repository network.
    #
    # Sets `maintenance_status` to `scheduled` and updates `last_maintenance_attempted_at` to the current time.
    #
    # Also enqueues a NetworkMaintenanceJob on the maintenance queue of the first healthy replica of the given
    # repository network.
    #
    def schedule_maintenance
      maintenance_queue_name.map do |queue_name|
        previous_status = maintenance_status
        update_status :scheduled, last_maintenance_attempted_at: Time.now
        NetworkMaintenanceJob.set(queue: queue_name).perform_later(id,
          previous_status: previous_status)
      end
    end

    def mark_as_broken
      update_status :broken
      instrument :mark_as_broken
    end

    # Make sure that the DGit replicas are all linked, or all not-linked.
    def ensure_dgit_replicas_link_consistently
      res = rpc.all_replicas_exist?
      fail if res.empty?
      return if res.values.uniq.size == 1

      repositories.each do |repo|
        repo.enable_shared_storage
      end
    end

    def network_corrupt?
      return false unless shared_storage_enabled?
      begin
        res = rpc.nw_fsck
        !res["ok"]
      rescue GitRPC::Protocol::DGit::ResponseError
        true
      end
    end

    def fork_corrupt?(repository)
      return false unless repository.exists_on_disk?
      begin
        res = repository.nw_fsck(trust_synced: true)
        !res["ok"]
      rescue GitRPC::Protocol::DGit::ResponseError
        true
      end
    end

    def find_corrupt_forks
      repositories.filter do |repository|
        Failbot.push(fork_id: repository.id) do
          fork_corrupt? repository
        end
      end
    end

    def check_restore_objects(r)
      begin
        res = r.restore_objects(max: 10000)
        return :fixed if res["ok"] && res["err"] =~ /objects? (was|were) restored/
      rescue GitRPC::Protocol::DGit::ResponseError
      end
      :corrupt
    end

    def check_network
      if network_corrupt?
        return check_restore_objects(rpc)
      end

      corrupt_forks = find_corrupt_forks
      return :ok if corrupt_forks.empty?
      corrupt_forks.each do |repository|
        Failbot.push(fork_id: repository.id) do
          if repository.exists_on_disk?
            return check_restore_objects(repository)
          end
        end
      end

      :corrupt
    rescue GitRPC::Timeout => e
      :timed_out
    rescue StandardError => e
      # Arbitrary exception. Be sure to catch, because we are already in a
      # rescue statement when calling check_network. Return the message.
      e.message
    end

    def update_status_on_failure(previous_status, maintenance_retries)
      if previous_status == "spurious_failure" && maintenance_retries >= 2
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
    end

    # Run maintenance on this network.
    #
    # This typically isn't called directly but run from the RepositoryNetworkMaintenance job.
    #
    # On success, `maintenance_status` will be set to `complete`, failures will set it to `failed`.
    # Recoverable errors will set `maintenance_status` to `retry`, which is treated like `complete` repository networks
    #
    # `last_maintenance_at` will only be updated when:
    #  * network maintenance completes successfully
    #
    # and reflects the time when the job finished.
    #
    # `last_maintenance_attempted_at` is updated when:
    #  * a network maintenance job is enqueued for a given network
    #  * a network maintenance job hits a recoverable error and puts the network into `retry` state
    #
    # and reflects the time when the job was enqueued or started.
    #
    def perform_maintenance(previous_status = :scheduled)
      started_at = Time.now
      pushed_count_at_start = pushed_count
      update_status :running

      maintenance_threshold = FULL_REPACK_THRESHOLD

      maintenance_count_since_full_at_start = maintenance_count_since_full
      geometric = maintenance_count_since_full_at_start < maintenance_threshold

      ensure_dgit_replicas_link_consistently

      # calculate disk usage for the entire network storage directory. we do
      # this before the maintenance so disk usage info is available even if
      # the job fails.
      root.setup_missing_git_repository if !root.exists_on_disk?
      calculate_disk_usage!

      unless enough_space_to_run_maintenance?
        update_status :retry, last_maintenance_attempted_at: started_at
        GitHub.logger.error("skipping maintenance due to insufficient disk space")
        return
      end

      # Don't attempt a gc if any non-DORMANT replicas are unhealthy
      # (down or non-ACTIVE).  It would just be wasted work, as the
      # unhealthy replica will be poorly packed when it comes back.
      ActiveRecord::Base.connected_to(role: :reading) do
        if !rpc.backend.delegate.replicas_healthy?
          ActiveRecord::Base.connected_to(role: :writing) do
            update_status :retry, last_maintenance_attempted_at: started_at
          end
          GitHub.logger.error("skipping maintenance due to unhealthy replicas")
          return
        end
      end

      # gc all non-alternated repositories
      #
      # We can't rely on a `pushed_at` filter here since pushes that fail post-rx checks will
      # increment the push counter but don't update `pushed_at` since the latter is user-visible
      repo_repack_start = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      repositories.each do |repository|
        Failbot.push fork_id: repository.id

        if repository.exists_on_disk? && !repository.shared_storage_enabled?
          GitHub.logger.info("starting repack for non-alternated repo",
                             "gh.spokes.spec" => repository.dgit_spec,
                             "gh.spokes.maintenance.is_repack" => true,
                             "gh.spokes.maintenance.is_geometric_repack" => geometric)
          repository.repack(geometric: geometric)
        end

        Failbot.pop
      end

      if shared_storage_enabled?
        GitHub.logger.info("starting repack of network",
                           "gh.spokes.maintenance.is_repack" => true,
                           "gh.spokes.maintenance.is_geometric_repack" => geometric)
        repack(geometric: geometric)
      end

      repo_repack_end = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      repack_duration = repo_repack_end - repo_repack_start

      # calculate disk usage for the entire network storage directory again now
      # that we've repacked and whatnot.
      previous_disk_usage = disk_usage
      disk_usage = calculate_disk_usage
      disk_usage_delta = disk_usage - previous_disk_usage

      GlobalInstrumenter.instrument("git.maintenance", {
        network_id: id,
        repository_count: repositories.count,
        is_geometric_repack: geometric,
        is_shared_storage_enabled: shared_storage_enabled?,
        maintenance_retries: maintenance_retries,
        pushed_count: pushed_count,
        pushed_count_since_maintenance: (pushed_count - pushed_count_at_start),
        disk_usage: disk_usage,
        disk_usage_delta: disk_usage_delta,
        repack_duration_in_seconds: repack_duration,
        completed_at: Time.now,
      })

      # reload to get latest pushed_count and update status
      reload
      update_status :complete,
        disk_usage: disk_usage,
        last_maintenance_at: Time.now,
        pushed_count_since_maintenance: (pushed_count - pushed_count_at_start),
        unpacked_size_in_mb: 0,
        maintenance_count_since_full:
          geometric ? maintenance_count_since_full_at_start + 1 : 0
      # Note: if a new pack is received during maintenance, it won't be
      # counted in the unpacked_size_in_mb until the next push.
    rescue *RETRYABLE_ERRORS => e
      # Repository offline or other temporary failure; try again later
      update_status :retry, last_maintenance_attempted_at: started_at
      GitHub.logger.error("temporary error, trying again later", e)
    rescue GitRPC::Timeout => e
      # The RPC operation timed out. This repository is probably very big.
      # Skip check_network as that will cause extra time in the job, and just move
      # to a spurious failure (unless it is continuously failing).
      update_status_on_failure(previous_status, maintenance_retries)
      raise
    rescue => boom # rubocop:todo Lint/GenericRescue
      check_network_result = check_network
      case check_network_result
      when :fixed
        GitHub.logger.error("repository had corruption, which was fixed")
        GitHub.dogstats.increment("git_maintenance.corruption", tags: ["type:network", "result:fixed"])
        update_status(:retry)
        return
      when :corrupt
        GitHub.logger.error("repository has corrupt forks")
        GitHub.dogstats.increment("git_maintenance.corruption", tags: ["type:network", "result:corrupted"])
        # TODO consider marking the repository as failed in this case.
        # We don't do this now to avoid additional toil while testing
        # this.
      when :timed_out
        GitHub.logger.error("repository timed out while checking for corruption")
        GitHub.dogstats.increment("git_maintenance.timed_out", tags: ["type:network", "result:timed_out"])
      else
        GitHub.logger.error("repository errored while checking for corruption: #{check_network_result}")
        GitHub.dogstats.increment("git_maintenance.error", tags: ["type:network", "result:error"])
      end
      update_status_on_failure(previous_status, maintenance_retries)
      raise
    end

    # Find all repositories in the network that were modified since the last
    # time maintenance was performed. If maintenance has never been performed
    # for the network, all repositories are returned.
    def repositories_modified_since_last_maintenance
      conditions = nil
      conditions = ["pushed_at >= ?", last_maintenance_at] if last_maintenance_at
      repositories.where(conditions).order(:id).to_a
    end

    # Internal: Update the network record's maintenance_status in the database.
    #
    # value - One of the maintenance status values as a string.
    #
    # Returns nothing.
    def update_status(value, attributes = {})
      attributes = attributes.merge(maintenance_status: value.to_s)
      update!(attributes)
    end

    # Internal: The queue where maintenance jobs should be scheduled
    # for this network.
    def maintenance_queue_name
      if !@dgit_maintenance_host
        all_replicas = GitHub::DGit::Routing.all_network_replicas(id)
        replica = all_replicas.find(&:healthy?)
        if !replica
          # The network is unrouted. Fall back on unhealthy or
          # offline replicas. (We're queueing a job; it can wait
          # until the chosen replica comes back.)
          replica = all_replicas.find(&:online?) ||
                    all_replicas.first
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
  end
end
