# typed: false
# frozen_string_literal: true

require "github/partition_usage"

module GitHub::Pages::Allocator
  extend self

  class AllocationFailed < StandardError
  end

  # Finds the hosts with the greatest amount of free space on their storage disks.
  # Calculates based on percentage of free space.
  # If site_size_kb is given, then hosts returned will have available storage space at least as large as site_size_kb
  #
  # is_voting -- the Boolean value of whether the host is "voting" or not.
  # min_replicas -- the Integer number of hosts to select
  # data_center -- (optional) the String value of the datacenter to limit results on (e.g. "cp1", "va3", "us-east-1")
  # site_size_kb -- (optional) the Integer kilobyte size of the site being written to the storage tier.
  #
  # Returns an Array of hosts which have the greatest amount of free disk space.
  def least_loaded_hosts(is_voting:, min_replicas: nil, data_center: nil, site_size_kb: nil)
    return [] if min_replicas.is_a?(Integer) && min_replicas <= 0

    if is_voting
      min_replicas ||= GitHub.pages_replica_count
    else
      min_replicas ||= GitHub.pages_non_voting_replica_count
    end

    return [] if min_replicas.nil?

    hosts = query_hosts(
      limit: min_replicas,
      non_voting: is_voting ? 0 : 1,
      min_size_kb: site_size_kb || 0,
      data_center: data_center,
      order_by: "disk_free DESC, host ASC"
    )

    if hosts.length != min_replicas
      raise AllocationFailed, "could not find #{min_replicas} online #{is_voting ? "voting" : "non-voting"} fileservers"
    end

    GitHub.dogstats.increment("pages.allocation_strategy.least_loaded_hosts")
    Array(hosts)
  end

  # Finds the hosts based on the build_id
  # The available hosts list is sorted
  # The mod (build_id) % (the number of hosts) is used to select hosts
  # If site_size_kb is given, then hosts returned will have available storage space at least as large as site_size_kb
  #
  # is_voting -- the Boolean value of whether the host is "voting" or not.
  # min_replicas -- the Integer number of hosts to select
  # data_center -- (optional) the String value of the datacenter to limit results on (e.g. "cp1", "va3", "us-east-1")
  # site_size_kb -- (optional) the Integer kilobyte size of the site being written to the storage tier.
  #
  # Returns an Array of hosts based on the build_id
  def build_based_hosts(build_id:, is_voting:, min_replicas: nil, data_center: nil, site_size_kb: 0)
    return [] if min_replicas.is_a?(Integer) && min_replicas <= 0

    if is_voting
      min_replicas ||= GitHub.pages_replica_count
    else
      min_replicas ||= GitHub.pages_non_voting_replica_count
    end

    return [] if min_replicas.nil?

    available_hosts = query_hosts(
      non_voting: is_voting ? 0 : 1,
      min_size_kb: site_size_kb,
      data_center: data_center,
      order_by: "host ASC"
    )

    if available_hosts.length < min_replicas
      raise AllocationFailed, "could not find #{min_replicas} online #{is_voting ? "voting" : "non-voting"} fileservers"
    end

    round_robin_index = build_id % available_hosts.length
    available_hosts.rotate(round_robin_index)[0, min_replicas].tap do
      GitHub.dogstats.increment("pages.allocation_strategy.build_based_hosts")
    end
  end

  # Fetch a list of voting and non-voting hosts and create a Hash
  # encapsulating each.
  #
  # build_id -- the build id is used to get the index to the host in a given available list
  # voting -- the Integer number of voting hosts to return.
  # non_voting -- the Integer number of non-voting hosts to return.
  # site_size_kb -- (optional) the Integer kilobyte size of the site being written to the storage tier.
  #
  # Returns a Hash with 2 keys: :voting, and :non_voting. Each key has a corresponding value of an Array of host names.
  def hosts_for_new_replicas(build_id:, voting:, non_voting:, site_size_kb: 0, replication_strategy: nil)
    replication_strategy ||= GitHub::Pages::ReplicationStrategy.new(replica_counts: voting)
    voting_hosts = replication_strategy.distribute do |data_center, replica_count|
      GitHub.dogstats.count("pages.allocate", replica_count, tags: ["voting:true", "datacenter:#{data_center}", "strategy:#{replication_strategy}"])
      if build_based_allocation_enabled?
        build_based_hosts(build_id: build_id, is_voting: true, min_replicas: replica_count, site_size_kb: site_size_kb, data_center: data_center)
      else
        least_loaded_hosts(is_voting: true, min_replicas: replica_count, site_size_kb: site_size_kb, data_center: data_center)
      end
    end

    GitHub.dogstats.count("pages.allocate", non_voting || 0, tags: ["voting:false", "strategy:none"])
    if build_based_allocation_enabled?
      non_voting_hosts = build_based_hosts(build_id: build_id, is_voting: false, min_replicas: non_voting, site_size_kb: site_size_kb)
    else
      non_voting_hosts = least_loaded_hosts(is_voting: false, min_replicas: non_voting, site_size_kb: site_size_kb)
    end
    { voting: voting_hosts, non_voting: non_voting_hosts }
  end

  def get_hosts
    ApplicationRecord::Pages.connection.select_values(Arel.sql(<<-SQL))
      SELECT host FROM pages_fileservers
        WHERE online = 1
          AND host != 'localhost'
    SQL
  end

  def update_disk_usage!(hostname:)
    info = GitHub::PartitionUsage.df([GitHub.pages_dir]).first
    inodes_info = GitHub::PartitionUsage.df_i([GitHub.pages_dir]).first

    sql_context = {
      hostname: hostname,
      disk_free: info.free,
      disk_used: info.used,
      inodes_free: inodes_info.free,
      inodes_used: inodes_info.used,
    }

    ApplicationRecord::Pages.connection.update(Arel.sql(<<-SQL, **sql_context))
      UPDATE
        pages_fileservers
      SET
        disk_free  = :disk_free,
        disk_used  = :disk_used,
        inodes_free = :inodes_free,
        inodes_used = :inodes_used,
        updated_at = NOW()
      WHERE host = :hostname
    SQL
  end

  private

  def build_based_allocation_enabled?
    # Leverage the FlipperHost in a way to support using datacenters instead of hostnames
    current_datacenter_actor = GitHub::FlipperHost.new(GitHub.datacenter)
    FeatureFlag.vexi.enabled_or_raise?(:pages_build_based_allocation_enabled, current_datacenter_actor) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
  end

  def query_hosts(non_voting:, min_size_kb:, limit: nil, data_center: nil, order_by: nil)
    binds = {
      non_voting: non_voting,
      min_size_kb: min_size_kb,
      data_center: data_center
    }

    query = Arel.sql(<<-SQL, **binds)
      SELECT host FROM pages_fileservers
      WHERE online = 1 AND embargoed = 0 AND non_voting = :non_voting AND disk_free > :min_size_kb
    SQL
    query += Arel.sql("AND datacenter = :data_center", **binds) if !GitHub.enterprise? && data_center.present? && data_center != GitHub.default_datacenter
    query += Arel.sql("ORDER BY #{order_by}") if order_by.present?
    query += Arel.sql("LIMIT :limit", limit: Arel.sql(limit.to_s)) if limit.present?
    ApplicationRecord::Pages.connection.select_values(query)
  end
end
