# typed: false
# frozen_string_literal: true

# Queries to see which storage objects need maintenance

require "github/config/mysql"
require "github/config/redis"
require "github/media_blob"
require "github/slice_query"

module GitHub::Storage
  class ClusterRepair
    include SliceQuery

    # results limit, this correlates to the number of jobs started
    def self.query_limit
      5000
    end

    def self.query_namespace
      "storage"
    end

    def self.query_name(non_voting, datacenter)
      non_voting ? "bad-non-voting-counts-#{datacenter}" : "bad-replica-counts"
    end

    def self.replica_count(non_voting, datacenter)
      non_voting ? GitHub::Storage::Allocator.non_voting_replica_count(datacenter) : GitHub.storage_replica_count
    end

    # Returns the number of objects to repair
    def self.perform(backing_up: nil, non_voting: false, datacenter: "default")
      copies = replica_count(non_voting, datacenter)
      return 0 if copies < 1
      blob_counts = get_bad_replica_counts(copies: copies, non_voting: non_voting, limit: query_limit, datacenter: datacenter)
      blob_counts.each do |(_id, oid, count)|
        if count.to_i < copies
          StorageReplicateObjectJob.perform_later({ "oid" => oid, "non_voting" => non_voting, "datacenter" => datacenter })
        elsif !backing_up
          StoragePurgeObjectJob.perform_later({ "oid" => oid, "non_voting" => non_voting, "datacenter" => datacenter })
        end
      end
      blob_counts.size
    end

    # Performs a `ClusterRepair` operation on the voting cluster
    def self.perform_voting(backing_up: nil)
      perform(backing_up: backing_up)
    end

    # Performs a `ClusterRepair` operation on the non-voting cluster within
    # the specified datacenter
    def self.perform_non_voting(datacenter, backing_up: nil)
      perform(backing_up: backing_up, non_voting: true, datacenter: datacenter)
    end

    # Gets the list of over/under-replicated blobs within the cluster currently
    # being repaired, as well as the number of replicas on which each of those
    # blobs exist
    def self.get_bad_replica_counts(copies: nil, non_voting: false, limit: nil, slice: true, datacenter: "default")
      copies ||= replica_count(non_voting, datacenter)
      limit ||= query_limit
      key = query_name(non_voting, datacenter)

      if slice
        start_time, offset, slices = get_query_slice(key)
        offset, next_offset = get_contiguous_id_range("storage_blobs", ApplicationRecord::Domain::Storage, offset, slices)
      else
        offset = next_offset = nil
      end

      fileserver_hosts = get_fileserver_hosts(non_voting, datacenter)
      results = GitHub::Storage::Replica.get_bad_replica_counts(
        offset, next_offset, copies, fileserver_hosts, limit)

      if slice
        if results.size >= limit
          next_offset = results.map { |row| row[0] }.max
          put_adjusted_query_slice(key, start_time, offset, next_offset, slices, no_adjustment: true)
        else
          put_adjusted_query_slice(key, start_time, offset, next_offset, slices)
        end
      end

      results
    end

    # Performs a `ClusterRepair` operation on the (non-voting) cache replicas
    # within each datacenter
    def self.perform_non_voting_cached(backing_up: nil)
      blob_counts = get_bad_cache_replica_counts(limit: query_limit)
      blob_counts.each do |_padding, oid, count, datacenter, cache_location, expected_count|
        if count < expected_count
          StorageReplicateObjectJob.perform_later({ "oid" => oid, "non_voting" => true, "datacenter" => datacenter, "cache_location" => cache_location, "cache_replica_count" => expected_count })
        elsif !backing_up
          StoragePurgeObjectJob.perform_later({ "oid" => oid, "non_voting" => true, "datacenter" => datacenter, "cache_location" => cache_location, "cache_replica_count" => expected_count })
        end
      end
      blob_counts.size
    end

    # Gets the list of over/under-replicated blobs within all cache locations,
    # as well as the number of replicas on which each of those blobs exist.
    # Note that for compatibility the returned arrays have an extra (empty)
    # leading element.
    def self.get_bad_cache_replica_counts(limit: nil, slice: true)
      datacenter_cache_locations = GitHub::Storage::Allocator.get_non_voting_datacenter_cache_locations(online: true)
      return [] if datacenter_cache_locations.size == 0

      # Construct map from cache locations to their configured default
      # cache policy's replication count.  Note that some cache locations
      # may not have configured default policies.
      default_replica_counts = {}
      GitHub::DGit::Util.default_cache_replica_counts(GitHub::DGit::RepoType::NETWORK).each do |cache_location, default_replica_count|
        default_replica_counts[cache_location] = default_replica_count
      end

      # Construct map from cache locations to lists of all datacenters
      # for each cache location, and also backfill any missing
      # default replication counts for all cache locations.
      datacenters = Hash.new { |h, k| h[k] = [] }
      datacenter_cache_locations.each do |datacenter, cache_location|
        datacenters[cache_location].push(datacenter)
        default_replica_counts[cache_location] ||= 0
      end

      # Construct map from datacenter and cache location pairs to
      # lists of fileserver hosts in each datacenter and cache location.
      fileserver_hosts = Hash.new { |h, k| h[k] = Hash.new { |h, k| h[k] = [] } }
      get_cache_location_fileserver_hosts.each do |datacenter, cache_location, host|
        fileserver_hosts[datacenter][cache_location].push(host)
      end

      limit ||= query_limit
      key = "bad-non-voting-cache-replica-counts"

      if slice
        start_time, offset, slices = get_query_slice(key)
        offset, next_offset = get_contiguous_id_range("media_blobs", ApplicationRecord::Domain::Assets, offset, slices)
      else
        offset = next_offset = nil
      end

      # Retrieve next slice of LFS object IDs and corresponding repository
      # network IDs (or all of them if not slicing).
      object_networks = GitHub::MediaBlob.get_object_repository_networks(offset, next_offset, limit)

      if slice
        if object_networks.size >= limit
          next_offset = object_networks.map { |row| row[0] }.max
          put_adjusted_query_slice(key, start_time, offset, next_offset, slices, no_adjustment: true)
        else
          put_adjusted_query_slice(key, start_time, offset, next_offset, slices)
        end
      end

      # For each LFS object ID and repository network ID, iterate through
      # all datacenter and cache location pairs and add to the result list
      # if the object is incorrectly replicated in that datacenter and
      # cache location.
      results = []
      network_replica_counts = Hash.new { |h, k| h[k] = {} }
      object_networks.each do |_id, oid, network_id|
        # For this object, iterate through all possible cache locations.
        datacenters.each_key do |cache_location|
          # If we have already determined the appropriate replication count
          # for this cache location, we can use it; otherwise we need to
          # determine it.  Note that it may be zero.
          network_replica_count = network_replica_counts[network_id][cache_location]
          if network_replica_count.nil?
            # Retrieve the configured replication count for this cache
            # location and repository network from the cache policy, if any.
            # If none is found, use the default for this cache location,
            # which again may be zero.
            network_replica_count = GitHub::DGit::Util.cache_replica_count(GitHub::DGit::RepoType::NETWORK, network_id, cache_location)
            if network_replica_count.nil?
              network_replica_count = default_replica_counts[cache_location]
            end
            network_replica_counts[network_id][cache_location] = network_replica_count
          end

          # For each datacenter in this cache location, retrieve the number
          # of replicas of the object in the datacenter and cache location,
          # and compare it to the number we are expecting, which is the
          # minimum of the configured cache policy replication count and the
          # actual number of available fileserver hosts in the datacenter and
          # cache location.  If the numbers differ, add the object's data to
          # the list of results to return.
          datacenters[cache_location].each do |datacenter|
            count = GitHub::Storage::Replica.get_replica_count_for_oid(oid, fileserver_hosts[datacenter][cache_location])
            expected_count = [network_replica_count, fileserver_hosts[datacenter][cache_location].size].min
            if count != expected_count
              results.push([nil, oid, count, datacenter, cache_location, expected_count])
            end
          end
        end
      end

      results
    end

    # Gets the list of online hosts within the cluster currently being repaired,
    # excluding any hosts in cache locations.
    def self.get_fileserver_hosts(non_voting, datacenter)
      sql = Arel.sql(<<-SQL, non_voting: non_voting)
        SELECT fs.host FROM storage_file_servers fs
        WHERE fs.non_voting = :non_voting
          AND fs.online = 1
          AND cache_location IS NULL
      SQL

      if non_voting
        sql += Arel.sql "AND fs.datacenter = :datacenter", datacenter: datacenter
      end

      ApplicationRecord::Domain::Storage.connection.select_values(sql)
    end

    # Gets the list of online hosts in cache locations within the cluster
    # currently being repaired.
    def self.get_cache_location_fileserver_hosts
      ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL))
        SELECT fs.datacenter, fs.cache_location, fs.host FROM storage_file_servers fs
         WHERE fs.non_voting = 1
           AND fs.online = 1
           AND cache_location IS NOT NULL
      SQL
    end
  end
end
