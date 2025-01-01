# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class SpokesDestroyNetworkReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  REPO_REPLICA_BATCH_SIZE = 100

  resolve_tenant_context do |network_id|
    ::RepositoryNetworks::Public.resolve_tenant(id: network_id)
  end

  def perform(network_id, host, **opts)
    Failbot.push spec: "network/#{network_id}",
                 app: "github-dgit"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "network/#{network_id}") do
      GitHub.logger.info("start", "code.function" => "perform")
      GitHub.dogstats.time("dgit.actions.destroy-network", tags: ["server:#{host}"]) do
        perform!(network_id, host)
      end
    end
  rescue Freno::Throttler::Error
  # Ignore freno errors and rely on retries from our own maintenance scheduler
  rescue GitHub::DGit::ReplicaDestroyNotFoundError
    # Ignore. This is possible due to races.
  end

  def perform!(network_id, host)
    replica = GitHub::DGit::Routing.network_replica_for_host(network_id, host)
    raise GitHub::DGit::ReplicaDestroyNotFoundError, "Network #{network_id} on #{host} not found" unless replica

    return unless GitHub::DGit::Maintenance.set_network_state(network_id, host, GitHub::DGit::DESTROYING)

    path = GitHub::Routing.nw_storage_path(network_id: network_id)
    rpc = replica.to_route(path).build_maint_rpc
    path = GitHub::DGit.dev_route(path, host) if Rails.env.development? || Rails.env.test? # rubocop:disable GitHub/DoNotBranchOnRailsEnv
    pattern = %r{^#{GitHub.repository_root}/(?:dgit\d{1,2}/)?[0-9a-f]/nw/[0-9a-f]{2}/[0-9a-f]{2}/[0-9a-f]{2}/\d+$}
    raise GitHub::DGit::ReplicaDestroyError, "Refusing to delete unexpected path #{path.inspect}" unless path =~ pattern

    GitHub.stats.increment "dgit.#{host}.actions.destroy" if GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["host:#{host}", "action:destroy"]

    begin
      if replica.online?
        GitHub.logger.info(
          "start",
          "code.namespace" => "GitRPC",
          "code.function" => "destroy_network_replica",
          "gh.spokes.storage_path" => path
        )
        rpc.destroy_network_replica(path)
      end
    rescue ::GitRPC::ConnectionError, SocketError => e
    end

    # Order for these next three steps is important.
    # - Deleting the network_replicas row should be last, because its absence
    #   is what indicates that the destroy succeeded.  If it's still there as
    #   state=DESTROYING, then this operation will get retryed as needed.
    # - Schedule the creation event before deleting the network_replicas
    #   row, so that the creation event can avoid the host with to-be-deleted
    #   replica when picking a host on which to place the to-be-created
    #   replica.

    db = GitHub::DGit::DB.for_network_id(network_id)

    network_replica_id = db.SQL.value(<<-SQL, network_id: network_id, host: host)
      SELECT id
      FROM network_replicas
      WHERE network_id = :network_id
      AND host = :host
    SQL

    # Delete repository replicas in batches of REPO_REPLICA_BATCH_SIZE until there
    # are no more left to delete.
    loop do
      results = with_write do
        db.throttle do
          db.SQL.run(<<-SQL, network_id: network_id, network_replica_id: network_replica_id, batch_size: REPO_REPLICA_BATCH_SIZE)
            DELETE FROM repository_replicas
            WHERE network_replica_id = :network_replica_id
            LIMIT :batch_size
          SQL
        end
      end

      break if results.affected_rows < REPO_REPLICA_BATCH_SIZE
    end

    # Delete the row from network_replicas. This is the final indicator of success.
    db.throttle do
      GitHub::DGit::Maintenance.delete_network_replica_for_host(network_id, host)
    end

    # check read-weight total
    GitHub::DGit::Maintenance.rebalance_read_weight(network_id)
  end
end
