# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# StoragePurgeObjectJob takes the oid of an overreplicated object and removes
# it from enough nodes to meet the GitHub.storage_replica_count quota.
#
# This job gets queued from StorageClusterMaintenanceSchedulerJob.perform
class StoragePurgeObjectJob < ApplicationJob
  queue_as :storage_cluster

  locked_by timeout: 1.hour, key: ->(job) {
    ::StorageReplicateObjectJob.convert_to_hash_args(job.arguments[0])
  }

  def perform(oid_or_hash)
    args = ::StorageReplicateObjectJob.convert_to_hash_args(oid_or_hash)
    oid = args["oid"]
    if args["non_voting"]
      if args["cache_location"].nil?
        purge(oid,
          hosts: GitHub::Storage::Allocator.non_voting_hosts_for_oid(oid, args["datacenter"]),
          limit: GitHub::Storage::Allocator.non_voting_replica_count(args["datacenter"]))
      else
        purge(oid,
          hosts: GitHub::Storage::Allocator.non_voting_cache_hosts_for_oid(oid, args["datacenter"], args["cache_location"]),
          limit: args["cache_replica_count"])
      end
    else
      purge(oid,
        hosts: GitHub::Storage::Allocator.cluster_hosts_for_oid(oid),
        limit: GitHub.storage_replica_count)
    end
  end

  def purge(oid, hosts:, limit:)
    return if hosts.size <= limit

    purge_from = hosts.sample(hosts.size - limit)
    purge_from.each do |host|
      ok, _ = GitHub::Storage::Client.delete(host, [oid])
      if ok
        with_write { GitHub::Storage::Creator.delete_replica_from_host(host, oid) }
      end
    end
  end
end
