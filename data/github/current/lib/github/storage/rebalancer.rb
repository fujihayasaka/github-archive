# typed: true
# frozen_string_literal: true

require "github/config/mysql"
require "github/config/redis"

module GitHub::Storage
  class Rebalancer
    MAX_DISK_SPACE_SPREAD = 0.1
    MIN_REBALANCING_AGE = 60 # minutes
    REBALANCING_SAMPLE = 100

    # Generates and queues `StorageClusterMoveObjectJob`s to rebalance the
    # voting cluster. Jobs are generated and queued based on free disk space.
    # If the voting cluster is already balanced, the Rebalancer won't make
    # any changes.
    def self.perform
      # Rebalancing should only run when there are more nodes than storage_replica_count, otherwise
      # the cluster should already be balanced because every node gets a copy of every object.
      hosts = GitHub::Storage::Allocator.get_hosts
      return if hosts.size == GitHub.storage_replica_count

      jobs = get_rebalancing_jobs(hosts, GitHub::Storage::Allocator.get_hosts(exclude_embargoed: true))
      jobs.each do |oid, from_host, to_host|
        StorageClusterMoveObjectJob.perform_later(oid, from_host, to_host)
      end
    end

    # Generates and queues `StorageClusterMoveObjectJob`s to rebalance the
    # non-voting cluster in the specified datacenter. Jobs are generated and
    # queued based on free disk space. If the cluster is already balanced,
    # the Rebalancer won't make any changes.
    def self.perform_non_voting(datacenter)
      hosts = GitHub::Storage::Allocator.get_non_voting_hosts(datacenter)
      return if hosts.size == GitHub::Storage::Allocator.non_voting_replica_count(datacenter)

      jobs = get_rebalancing_jobs(hosts, GitHub::Storage::Allocator.get_non_voting_hosts(datacenter, exclude_embargoed: true))
      jobs.each do |oid, from_host, to_host|
        StorageClusterMoveObjectJob.perform_later(oid, from_host, to_host)
      end
    end

    # Generates and queues `StorageClusterMoveObjectJob`s to rebalance the
    # non-voting cluster in the specified datacenter and cache location. Jobs
    # are generated and queued based on free disk space. If the cluster is
    # already balanced, the Rebalancer won't make any changes.
    def self.perform_non_voting_cached(datacenter, cache_location)
      # Rebalancing should only run when there are more nodes than the lowest
      # replication factor for any repository network whose objects are cached
      # in this location.
      hosts = GitHub::Storage::Allocator.get_non_voting_cache_hosts(datacenter, cache_location)
      return if hosts.size <= GitHub::DGit::Util.min_cache_replica_count(GitHub::DGit::RepoType::NETWORK, cache_location)

      jobs = get_rebalancing_jobs(hosts, GitHub::Storage::Allocator.get_non_voting_cache_hosts(datacenter, cache_location, exclude_embargoed: true))
      jobs.each do |oid, from_host, to_host|
        StorageClusterMoveObjectJob.perform_later(oid, from_host, to_host)
      end
    end

    # Get the fraction of disk space available to storage objects
    # Returns an array with two elements:
    #   - a float between 0.0 and 1.0, the fraction of space available
    #   - the absolute size of the disk in MB
    #
    # If the call fails, return [0, 1] so the host can only be chosen if
    # everyone else also returns zero.
    def self.disk_stats(host)
      ok, stats = GitHub::Storage::Client.stats(host, ["0"])
      return [0, 1] if !ok
      used = stats["partitions"]["0"]["disk_used"].to_i / 1048576
      free = stats["partitions"]["0"]["disk_free"].to_i / 1048576
      total_size = used + free
      fraction = used / total_size.to_f
      [fraction, total_size]
    end

    STORAGE_CLUSTER_JOBS = [
      "::StorageClusterMoveObjectJob",
      "::StorageReplicateObjectJob",
      "::StoragePurgeObjectJob",
    ]

    def self.get_queued_objects
      storage_cluster_jobs = STORAGE_CLUSTER_JOBS.map(&:constantize)
      StorageClusterMoveObjectJob.queue_adapter
        .peek(queue: StorageClusterMoveObjectJob.queue_name, limit: 100)
        .select { |job| storage_cluster_jobs.include?(job.class) }
        .map { |job| job.arguments.first }
        .flatten.uniq
        .map { |oid| [oid, true] }
        .to_h
    end

    def self.get_some_objects_on(host)
      ActiveRecord::Base.connected_to(role: :reading) do
        sql = Arel.sql(<<-SQL, host: host, min_rebalancing_age: MIN_REBALANCING_AGE, limit: Arel.sql(REBALANCING_SAMPLE.to_s))
          SELECT storage_blobs.oid, storage_blobs.size FROM storage_blobs
          INNER JOIN storage_replicas
            ON storage_blobs.id = storage_replicas.storage_blob_id
          WHERE storage_replicas.host = :host
            AND storage_replicas.created_at < NOW() - INTERVAL :min_rebalancing_age MINUTE
          LIMIT :limit
        SQL
        sampled_oids = ApplicationRecord::Domain::Storage.connection.select_rows(sql)

        return [] if sampled_oids.empty?

        sampled_oids.shuffle.map { |oid, size| [oid, size / 1048576.to_f] }
      end
    end

    def self.pick_dest_for(oid, donor, recipients)
      hosts = GitHub::Storage::Allocator.hosts_for_oid(oid)
      candidates = recipients - hosts
      candidates.first
    end

    # Return value is rows like [oid, from_host, to_host]
    def self.get_rebalancing_jobs(hosts, hosts_not_embargoed)
      # Get the free disk space fraction for each host
      host_space = Hash[hosts.map do |host|
                          [host, disk_stats(host)]
                        end]
      return [] if host_space.empty?

      # Find hosts that are out of balance
      max_host_space = hosts_not_embargoed.map { |h| host_space[h].first }.max
      min_host_space = host_space.values.map(&:first).min
      return [] if max_host_space - min_host_space <= MAX_DISK_SPACE_SPREAD && max_host_space <= min_host_space * 2

      donors = host_space.select { |_, v| v.first < max_host_space - MAX_DISK_SPACE_SPREAD || v.first < max_host_space / 2 }.map(&:first)
      recipients = host_space.select { |_, v| v.first > min_host_space + MAX_DISK_SPACE_SPREAD || v.first > min_host_space * 2 }.map(&:first) & hosts_not_embargoed
      fail "no donor nodes found" if donors.empty?
      fail "no recipient nodes found" if recipients.empty?

      # Eliminate overlap
      overlap = donors & recipients
      donors -= overlap

      donors.sort! { |a, b| host_space[a].first <=> host_space[b].first }
      recipients.sort! { |a, b| host_space[b].first <=> host_space[a].first }

      # Find objects to move to get hosts back into balance
      ret = []
      already_moved = get_queued_objects

      donors.each do |donor|
        objects = get_some_objects_on(donor)
        objects.each do |oid, size_in_mb|
          next if already_moved[oid]
          dest = pick_dest_for(oid, donor, recipients)
          next unless dest
          ret << [oid, donor, dest]
          already_moved[oid] = true
          host_space[donor][0] += size_in_mb.to_f / host_space[donor][1]
          host_space[dest][0] -= size_in_mb.to_f / host_space[dest][1]
          if host_space[dest].first <= min_host_space + MAX_DISK_SPACE_SPREAD &&
                                                        host_space[dest].first <= min_host_space * 2
            recipients.delete(dest)
          end
          if host_space[donor].first >= max_host_space - MAX_DISK_SPACE_SPREAD &&
                                                         host_space[donor].first >= max_host_space / 2
            break
          end
        end
      end
      ret
    end
  end
end
