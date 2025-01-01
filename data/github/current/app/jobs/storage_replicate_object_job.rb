# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

# StorageReplicateObjectJob takes the oid of an underreplicated object and
# ensures it is replicated on GitHub.storage_replica_count nodes.
#
# This job gets queued from StorageClusterMaintenanceSchedulerJob.perform
class StorageReplicateObjectJob < ApplicationJob
  queue_as :storage_cluster

  locked_by timeout: 1.hour, key: ->(job) {
    ::StorageReplicateObjectJob.convert_to_hash_args(job.arguments[0])
  }

  class Error < StandardError
  end

  def perform(oid_or_hash)
    args = ::StorageReplicateObjectJob.convert_to_hash_args(oid_or_hash)
    replicate(args["oid"], !!args["non_voting"], args["datacenter"], args["cache_location"], args["cache_replica_count"])
  end

  def replicate(oid, non_voting, datacenter, cache_location, cache_replica_count)
    if non_voting
      if cache_location.nil?
        limit = GitHub::Storage::Allocator.non_voting_replica_count(datacenter)
        hosts = GitHub::Storage::Allocator.non_voting_hosts_for_oid(oid, datacenter)
      else
        limit = cache_replica_count
        hosts = GitHub::Storage::Allocator.non_voting_cache_hosts_for_oid(oid, datacenter, cache_location)
      end
    else
      limit = GitHub.storage_replica_count
      hosts = GitHub::Storage::Allocator.cluster_hosts_for_oid(oid)
    end

    return if hosts.size >= limit

    if non_voting
      if cache_location.nil?
        replicas = GitHub::Storage::Allocator.least_loaded_non_voting_hosts(datacenter)
      else
        replicas = GitHub::Storage::Allocator.least_loaded_non_voting_cache_hosts(datacenter, cache_location, cache_replica_count)
      end
    else
      replicas = GitHub::Storage::Allocator.least_loaded_voting_hosts
    end

    replicas -= hosts
    if replicas.empty?
      GitHub.logger.info(
        "No online target hosts available for replication",
        {
          "code.function": __method__,
          "gh.storage_replicate_job.oid": oid,
          "gh.storage_replicate_job.non_voting": non_voting,
          "gh.storage_replicate_job.datacenter": datacenter
        }
      )
      return
    end

    origin_host = GitHub::Storage::Allocator.hosts_for_oid(oid).sample
    if origin_host.nil?
      GitHub.logger.info(
        "No online source hosts available for replication",
        {
          "code.function": __method__,
          "gh.storage_replicate_job.oid": oid,
          "gh.storage_replicate_job.non_voting": non_voting,
          "gh.storage_replicate_job.datacenter": datacenter
        }
      )
      return
    end

    send_to = replicas.sample(limit - hosts.size)

    ok, body = GitHub::Storage::Client.replicate_to(origin_host, [{
      oid: oid,
      fileservers: send_to.map { |host| GitHub.storage_replicate_fmt % host },
    }])

    if !ok
      GitHub.logger.info(
        "Server error on replicate_to: #{body}",
        {
          "code.function":  __method__,
          "gh.storage_replicate_job.oid": oid,
          "gh.storage_replicate_job.non_voting": non_voting,
          "gh.storage_replicate_job.datacenter": datacenter,
          "gh.storage_replicate_job.origin_host": origin_host
        }
      )
      raise Error, "Server error on replicate_to"
    end

    failed = []
    received = []
    Array(body["objects"]).each do |obj|
      Array(obj["success"]).each do |raw_url|
        received << URI.parse(raw_url).host
      end

      # fallback due to json structag typo
      # https://github.com/github/alambic/blob/2b1f21bc5c61613e3b3b231b3a8badcdf0b55e09/cluster/cluster.go#L592
      if errors = obj["errors"] || obj["Errors"]
        errors.each do |node, err|
          failed << "#{node}: #{err}"
        end
      end
    end

    if received.present?
      with_write { GitHub::Storage::Creator.create_replicas_for_oid(oid, received) }
    end

    if failed.present?
      GitHub.logger.info(
        "Error replicating to hosts",
        {
          "code.function": __method__,
          "gh.storage_replicate_job.oid": oid,
          "gh.storage_replicate_job.non_voting": non_voting,
          "gh.storage_replicate_job.datacenter": datacenter,
          "gh.storage_replicate_job.origin_host": origin_host,
          "gh.storage_replicate_job.failed": failed
        }
      )
      raise Error, "Error replicating #{oid}"
    end
  end

  def self.convert_to_hash_args(oid_or_hash)
    args = case oid_or_hash
    when String then { "oid" => oid_or_hash, "non_voting" => false }
    when Hash then oid_or_hash.stringify_keys
    else
      raise ArgumentError, "expected String OID or hash args, got: #{oid_or_hash.inspect}"
    end
  end
end
