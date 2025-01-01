# typed: true
# frozen_string_literal: true

require "github/config/mysql"

module GitHub
  module Storage
    autoload :Allocator, "github/storage/allocator"
    autoload :Client, "github/storage/client"
    autoload :ClusterConsensus, "github/storage/cluster_consensus"
    autoload :ClusterRepair, "github/storage/cluster_repair"
    autoload :Command, "github/storage/command"
    autoload :Creator, "github/storage/creator"
    autoload :DeleteOrphansCommand, "github/storage/delete_orphans_command"
    autoload :Destroyer, "github/storage/destroyer"
    autoload :Offline, "github/storage/offline"
    autoload :Online, "github/storage/online"
    autoload :PartitionStats, "github/storage/partition_stats"
    autoload :Rebalancer, "github/storage/rebalancer"
    autoload :RebuildHostCommand, "github/storage/rebuild_host_command"
    autoload :RepairUploadablesCommand, "github/storage/repair_uploadables_command"
    autoload :Replica, "github/storage/replica"
    autoload :ReplicaVerifier, "github/storage/replica_verifier"
    autoload :TestClient, "github/storage/test_client"
    autoload :Uploader, "github/storage/uploader"
  end
end
