# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesCreateNetworkReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  resolve_tenant_context do |network_id|
    ::RepositoryNetworks::Public.resolve_tenant(id: network_id)
  end

  def perform(network_id, host)
    Failbot.push spec: "network/#{network_id}", app: "github-dgit"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "network/#{network_id}") do
      GitHub.logger.info("start", "code.function" => "perform!")
      GitHub.dogstats.time("dgit.actions.create-network", tags: ["server:#{host}"]) do
        perform!(network_id, host, nil)
      end
    end
  rescue Freno::Throttler::Error
    # Ignore freno errors and rely on retries from our own maintenance scheduler
  rescue GitHub::DGit::ReplicaCreateAlreadyPresentError
    # Ignore this case. This race does still occur in practice, but it's not
    # very interesting.
  end

  def perform!(network_id, host, after_rsync = nil, strict = false)
    raise GitHub::DGit::ReplicaCreateError, "#{host} is not a DGit host" unless GitHub::DGit::get_hosts(storage_class: :all).include?(host)

    GitHub.stats.increment "dgit.#{host}.actions.create" if GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["action:create", "host:#{host}"]
    is_cache_replica = GitHub::DGit::get_hosts(server_type: :cache).include?(host)

    # Insert a new network replica.
    begin
      network_replica_id = with_write do
        db = GitHub::DGit::DB.for_network_id(network_id)
        sql = db.SQL.new \
          network_id: network_id,
          host: host,
          state: GitHub::DGit::CREATING
        sql.add <<-SQL
              INSERT INTO network_replicas (network_id, host, state, read_weight, created_at, updated_at)
                VALUES (:network_id, :host, :state, 0, NOW(), NOW())
        SQL
        db.throttle { sql.run }
        sql.last_insert_id
      end # connected_to
    rescue ActiveRecord::RecordNotUnique
      raise GitHub::DGit::ReplicaCreateAlreadyPresentError, "There is already a replica of network #{network_id} on #{host}"
    end

    # There's a bit of a race here.
    # - If someone deletes a fork from the network at this point, the
    #   DELETE associated with that will find no rows in
    #   repository_replicas matching <host,repo_id> to delete.  We may
    #   in fact end up adding <host,repo_id> right after it was
    #   supposed to be deleted.
    # - If someone creates a fork in the network right now, we may end
    #   up getting the same repository_replicas row inserted twice,
    #   and get a key conflict, which would make either the fork or
    #   the network-replica creation fail.
    # The cleanup process is to get network_replicas and
    # repository_replicas back in sync.
    # FIXME: take the fork lock, maybe?

    # The number of repository_replicas to insert in one query.
    batch_size = 100

    # The current batch of repository_replicas to be inserted. List of
    # [repo_id, repo_type].
    batch = []

    # If the batch is full, or if this is the final batch, insert the rows
    # and then clear it.
    process_batch = ->(final) do
      return if batch.empty?
      return if !final && batch.count < batch_size

      values = batch.map do |repo_id, repo_type|
        [
          repo_id,
          repo_type,
          network_replica_id,
          host,
          "creating",
          GitHub::SQL::NOW,
          GitHub::SQL::NOW
        ]
      end

      with_write do
        db = GitHub::DGit::DB.for_network_id(network_id)
        db.throttle do
          db.SQL.run(<<-SQL, network_id: network_id, values: GitHub::SQL::ROWS(values))
            INSERT INTO repository_replicas (repository_id, repository_type, network_replica_id, host, checksum, created_at, updated_at)
            VALUES :values
          SQL
        end
      end

      batch.clear
    end

    # Choose any active network replica to mirror the new repository replicas
    # from. It's not absolutely guaranteed that all of the repositories will
    # be present in all edge cases, but it's also not absolutely vital that
    # we insert 100% of them. The repository replica sweeper will insert any
    # missing repository replicas later.
    existing_network_replica_id = GitHub::DGit::Util.network_replicas(network_id)
        .select { |_id, _, state| state == GitHub::DGit::ACTIVE }
        .map { |id, _, _| id }
        .first

    if existing_network_replica_id.nil?
      raise GitHub::DGit::NotFoundError, "No active network replicas found for network #{network_id}"
    end

    any_replicas = false

    GitHub::DGit::Util.each_repository_replica_for_network_replica(network_id, existing_network_replica_id) do |repo_id, repo_type, _, _|
      batch.push([repo_id, repo_type])
      any_replicas = true
      process_batch.call(false)
    end

    process_batch.call(true)

    if !any_replicas
      # It's empty.  There's nothing to copy or checksum.
      # Q: Is this necessary? Can't `SpokesRepairNetworkReplicaJob` deal with empty networks for us?
      GitHub::DGit::Maintenance::set_network_state(network_id, host, GitHub::DGit::ACTIVE)
    else
      if is_cache_replica
        # Always mark cache replicas as ACTIVE.  We won't read from them
        # until the checksum is okay anyway, but we can't mark them ACTIVE
        # in the sync job because that doesn't have enough information.
        GitHub::DGit::Maintenance::set_network_state(network_id, host, GitHub::DGit::ACTIVE)

        unless repo_ids.empty?
          # Sync each repo into existence.  The sync job takes care fo
          # setting up the repo and getting all the data.
          repo_ids.map do |repo_id|
            GitHub.logger.info("start", "code.namespace" => "SpokesSyncCacheReplicaJob", "code.function" => "perform_now")
            SpokesSyncCacheReplicaJob.perform_now(repo_id, host)
          end
        end
      else
        # Repair it into existence.  Shazam.
        # Seriously, "network repair" and "network creation" are the same
        # big blob of rsyncs and checksum-checking.
        GitHub.logger.info("start", "code.namespace" => "SpokesRepairNetworkReplicaJob", "code.function" => "perform!")
        SpokesRepairNetworkReplicaJob.new.perform!(network_id, host, GitHub::DGit::CREATING, after_rsync, strict)
      end
    end

    # check read-weight total
    GitHub::DGit::Maintenance.rebalance_read_weight(network_id, new_host: host)

    # Catch repair errors here, but not creation errors.
    # Set the state to FAILED so one more repair attempt can be made
    # before it just gets destroyed.
  rescue GitHub::DGit::ReplicaRepairError => e
    GitHub::DGit::Maintenance::set_network_state(network_id, host, GitHub::DGit::FAILED)
    raise e
  end

end
