# typed: true
# frozen_string_literal: true

require "logger"
require "github/pages/management"

module GitHub::Pages::Management
  class ReallocateReplicas
    attr_reader :last_reallocated_replica
    attr_writer :last_reallocated_replica

    REPLICA_BATCH_MAX_DELAY = 10
    REPLICA_BATCH_SIZE = 50
    REPLICA_QUERY_MAX_ATTEMPTS = 10

    NoHostFoundError = Class.new(GitHub::Pages::Management::ExecutionError)
    InvalidDiskUsageError = Class.new(GitHub::Pages::Management::ExecutionError)
    NoReplicaFoundError = Class.new(GitHub::Pages::Management::ExecutionError)

    def initialize(delegate:, host:, voting:, datacenter:, target_disk_usage:, start_replica_id: nil, source_host: nil)
      @delegate = delegate
      @target_host = host
      @voting = voting
      @datacenter = datacenter
      @target_disk_usage = target_disk_usage
      @start_replica_id = start_replica_id || 1
      @source_host = source_host

      @last_reallocated_replica = Hash.new

      nil
    end

    def perform
      no_replica_found = 0

      while !disk_usage_at_target
        source_host = @source_host || find_highest_disk_usage_host

        if source_host == @target_host
          @delegate.log "The target host #{@target_host} now has the highest disk usage. Exiting."
          break
        end

        replicas_to_reallocate = find_replicas_to_reallocate(source_host: source_host)
        # To avoid ending up in an endless loop when there is no replica to reallocate, exit after 10 attempts
        if replicas_to_reallocate.blank?
          no_replica_found += 1
          break if no_replica_found == REPLICA_QUERY_MAX_ATTEMPTS

          next
        else
          no_replica_found = 0
        end

        replicas_to_reallocate.each do |replica|
          DpagesReallocateReplicaJob.perform_later([replica[:page_id], replica[:pages_deployment_id], @target_host, source_host, @voting])
        end

        @last_reallocated_replica[source_host] = replicas_to_reallocate.pluck(:id).max

        # Sleep in between batch of jobs for the queue to drain.
        # HACK: use the percentage of actors enabled for a feature flag to tweak sleep duration as needed
        delay = GitHub.flipper[:pages_replica_reallocate_delay].percentage_of_actors_value.fdiv(100) * REPLICA_BATCH_MAX_DELAY
        sleep(delay)
      end

      true
    end

    def disk_usage_at_target
      disk_usage = target_host_disk_usage

      disk_free = disk_usage[:disk_free]
      disk_used = disk_usage[:disk_used]

      @delegate.log("Disk free of host #{@target_host} at #{disk_free}")
      @delegate.log("Disk used of host #{@target_host} at #{disk_used}")

      if disk_used.fdiv(disk_free + disk_used) >= @target_disk_usage
        @delegate.log("Disk usage of host #{@target_host} reached target #{@target_disk_usage}")
        return true
      end

      false
    end

    def target_host_disk_usage
      binds = {
        host: @target_host
      }

      # Ideally we'd pull disk space from the host directly because data in db is refreshed per minute only
      # Not doing that for now to have flexibility of running this outside of the host and keep it simple
      # But should revisit later once we have better idea of how it goes
      results = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, **binds))
        SELECT disk_free, disk_used FROM pages_fileservers
        WHERE host = :host
      SQL

      raise NoHostFoundError if results.blank? || results.first.blank?

      disk_free = results.first.first
      disk_used = results.first.last
      raise InvalidDiskUsageError if disk_free + disk_used == 0

      { disk_free: disk_free, disk_used: disk_used }
    end

    def find_highest_disk_usage_host
      binds = {
        non_voting: @voting ? 0 : 1,
        datacenter: @datacenter
      }

      # Find both embargoed & unembargoed hosts. Intended to take replicas from embargoed nodes too.
      host = ApplicationRecord::Domain::Repositories.connection.select_value(Arel.sql(<<-SQL, **binds))
        SELECT host, disk_used / (disk_used + disk_free) as disk_usage FROM pages_fileservers
        WHERE online = 1
          AND non_voting = :non_voting
          AND datacenter = :datacenter
        ORDER BY disk_usage DESC LIMIT 1
      SQL

      raise NoHostFoundError if host.blank?

      @delegate.log "Host with highest disk usage is #{host}"

      host
    end

    # The final result attempts to finds the oldest replicas that satisfies the condition. A guess here is they would less chance of
    # starting a new build. Hence less opportunity of race condition while the reallocation is happening.
    def find_replicas_to_reallocate(source_host:)
      last_replica = @last_reallocated_replica[source_host] || 0

      binds = {
        source_host: source_host,
        target_host: @target_host,
        size: Arel.sql(REPLICA_BATCH_SIZE.to_s),
        start_from_id: [last_replica + 1, @start_replica_id].max
      }

      # Find replicas exists in `source_host` but not `target_host`
      # The query takes 0.01s on a staging cluster with production data, with the size limit to 50
      # If it takes more, we can cache the result for each host instead of hitting the db repeatedly
      results = ApplicationRecord::Domain::Repositories.connection.select_rows(Arel.sql(<<-SQL, **binds))
        SELECT id, page_id, pages_deployment_id FROM pages_replicas AS replicas_include
        WHERE host = :source_host
          AND id >= :start_from_id
          AND NOT EXISTS
          (
            SELECT page_id, pages_deployment_id FROM pages_replicas
            WHERE host = :target_host AND page_id = replicas_include.page_id AND pages_deployment_id = replicas_include.pages_deployment_id
          )
        ORDER BY id ASC limit :size
      SQL

      if results.blank?
        @delegate.log "Couldn't find any replicas that exists in source host #{source_host} but not #{@target_host}"
        return []
      end

      @delegate.log "#{results.size} replicas found exists in source host #{source_host} but not #{@target_host}"

      results.map { |r| { id: r[0], page_id: r[1], pages_deployment_id: r[2] } }
    end
  end
end
