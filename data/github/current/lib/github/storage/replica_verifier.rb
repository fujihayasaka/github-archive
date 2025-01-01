# typed: false
# frozen_string_literal: true

# Spawns jobs to verify each Alambic object.

require "github/config/mysql"
require "github/config/redis"
require "github/slice_query"

module GitHub::Storage
  class ReplicaVerifier
    include SliceQuery

    # results limit, this correlates to the number of jobs started
    def self.query_limit
      100
    end

    def self.query_namespace
      "storage"
    end

    def self.ttl
      # One month. Max possible TTL.
      30 * 24 * 60 * 60
    end

    def self.perform
      blob_counts, hosts = get_replicas(limit: query_limit)
      blob_counts.each do |(_id, oid, count)|
        if count.to_i > 0
          StorageReplicationVerificationJob.perform_later({ "oid" => oid, "hosts" => hosts.sort })
        end
      end
    end

    def self.get_replicas(limit: nil, slice: true)
      limit ||= query_limit

      if slice
        start_time, offset, slices = get_query_slice("storage-replica-verifier-counts")
        offset, next_offset = get_contiguous_id_range("storage_blobs", ApplicationRecord::Domain::Storage, offset, slices)

        # Don't rewind; this job only needs to run once per object.
        return [[], []] if rate_limited?("storage_blobs", offset, ttl: ttl)
      else
        offset = next_offset = nil
      end

      fileserver_hosts = ApplicationRecord::Domain::Storage.connection.select_rows(Arel.sql(<<-SQL))
        SELECT fs.host
        FROM storage_file_servers fs
        WHERE fs.online = 1
      SQL
      fileserver_hosts.flatten!
      results = GitHub::Storage::Replica.get_online_objects(
        offset, next_offset, fileserver_hosts, limit)

      if slice
        if results.size >= limit
          next_offset = results.map { |row| row[0] }.max
          put_adjusted_query_slice("storage-replica-verifier-counts", start_time, offset, next_offset, slices, no_adjustment: true)
        else
          put_adjusted_query_slice("storage-replica-verifier-counts", start_time, offset, next_offset, slices)
        end
      end

      [results, fileserver_hosts]
    end
  end
end
