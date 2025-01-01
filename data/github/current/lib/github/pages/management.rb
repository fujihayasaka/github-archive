# typed: true
# frozen_string_literal: true

module GitHub::Pages::Management
  autoload :AddReplica, "github/pages/management/add_replica"
  autoload :AddReplicaAzure, "github/pages/management/add_replica_azure"
  autoload :CheckReplicas, "github/pages/management/check_replicas"
  autoload :Delegate, "github/pages/management/delegate"
  autoload :DeletePathFromHostsDisk, "github/pages/management/delete_path_from_hosts_disk"
  autoload :Evacuate, "github/pages/management/evacuate"
  autoload :ExecutionError, "github/pages/management/execution_error"
  autoload :ListReplicas, "github/pages/management/list_replicas"
  autoload :Offline, "github/pages/management/offline"
  autoload :Online, "github/pages/management/online"
  autoload :ReallocateReplicas, "github/pages/management/reallocate_replicas"
  autoload :Remove, "github/pages/management/remove"
  autoload :RemoveReplica, "github/pages/management/remove_replica"
  autoload :Repair, "github/pages/management/repair"
  autoload :ReplicationStatus, "github/pages/management/replication_status"
  autoload :SetEmbargoed, "github/pages/management/set_embargoed"
  autoload :SetEvacuating, "github/pages/management/set_evacuating"
  autoload :SetFileserverAttribute, "github/pages/management/set_fileserver_attribute"
  autoload :SetVoting, "github/pages/management/set_voting"
  autoload :ShowFileserver, "github/pages/management/show_fileserver"
  autoload :Status, "github/pages/management/status"
  autoload :MigrateHost, "github/pages/management/migrate_host"
end
