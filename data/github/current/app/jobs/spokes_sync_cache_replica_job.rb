# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"
require "github/git_repository/maintenance_client"

# Using a combination of `git fetch` and `rsync`, bring a given
# repository replica back into compliance with other replicas for that
# repository.
class SpokesSyncCacheReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  def lock_contents
    "#{Socket.gethostname.split(".").first}##{Process.pid}"
  end

  def lock_name
    "dgit-repo-sync.lock"
  end

  def perform(repo_id, cache_host, is_wiki = false)
    Failbot.push app: "github-dgit"

    repo = Repository.find_by_id(repo_id)
    raise GitHub::DGit::ReplicaSyncError, "Repo ID #{repo_id} not found" unless repo

    Failbot.push spec: repo.dgit_spec(wiki: is_wiki)

    GitHub.logger.with_named_tags("gh.spokes.spec" => repo.dgit_spec(wiki: is_wiki)) do
      GitHub.logger.info("start", "code.function" => "perform!")
      perform!(repo, cache_host, is_wiki)
    end
  rescue Freno::Throttler::Error
  end

  def perform!(repo, cache_host, is_wiki = false, &block)
    start = nil
    our_lock = false
    repo_type = is_wiki ? GitHub::DGit::RepoType::WIKI : GitHub::DGit::RepoType::REPO
    replica = if is_wiki
      GitHub::DGit::Routing.wiki_replica_for_host(repo.id, cache_host)
    else
      GitHub::DGit::Routing.repo_replica_for_host(repo.id, cache_host)
    end
    raise GitHub::DGit::ReplicaSyncError, "Replica #{repo.id} on #{cache_host} not found" unless replica
    raise GitHub::DGit::ReplicaSyncError, "Replica #{repo.id} on #{cache_host} is not a cache replica" unless replica.fileserver.cache_server?

    maint_client = if is_wiki
      GitHub::GitRepository::MaintenanceClient.new repo, replica.to_route(repo.wiki_shard_path).build_maint_rpc
    else
      GitHub::GitRepository::MaintenanceClient.new repo, replica.to_route(repo.original_shard_path).build_maint_rpc
    end

    begin
      read_route = if !is_wiki
        repo.dgit_read_routes.first
      else
        repo.dgit_wiki_read_routes.first
      end
    rescue GitHub::DGit::UnroutedError => e
      GitHub.logger.error({ :exception => e, "code.namespace" => "Repository::GitDependency", "code.function" => "dgit_read_routes" })
      GitHub.logger.info("Sync failed: unrouted (no available read replica)")
      return
    end

    GitHub.dogstats.time("dgit.actions.sync-repo", tags: ["server:#{cache_host}"]) do
      start = Time.now
      GitHub.logger.info("DGit syncing #{is_wiki ? "wiki" : "repo"} replica #{repo.id} on #{cache_host} from source host #{read_route.original_host}")

      read_replica = if !is_wiki
        GitHub::DGit::Routing.repo_replica_for_host(repo.id, read_route.original_host)
      else
        GitHub::DGit::Routing.wiki_replica_for_host(repo.id, read_route.original_host)
      end

      synced_checksum = if is_wiki
        GitHub::DGit::Routing.wiki_checksum(repo.network_id, repo.id)
      else
        GitHub::DGit::Routing.repo_checksum(repo.network_id, repo.id)
      end

      reader_rpc = if is_wiki
        read_replica.to_route(repo.wiki_shard_path).build_maint_rpc
      else
        read_replica.to_route(repo.original_shard_path).build_maint_rpc
      end
      # rpc.fs_lock and git fetch won't work unless we have a repo
      # directory to play in.  It doesn't matter what's there, though,
      # because git fetch will overwrite everything.
      if !maint_client.rpc.exist?
        maint_client.rpc.init
        if reader_rpc.nw_linked?
          maint_client.rpc.nw_link
        end
      end

      # check to see if someone else has a lock
      if !maint_client.rpc.fs_lock(lock_name, lock_contents, 1.hour.to_i)
        GitHub.logger.info("Unable to get the sync lock")
        return
      end
      our_lock = true

      audit_log_size = 0
      if maint_client.rpc.fs_exist?("audit_log")
        audit_log_size = maint_client.rpc.fs_size("audit_log")
      end
      do_fetch(read_route, maint_client.rpc, cache_host, repo.id, repo_type, is_wiki, start)
      updated_refs = read_updated_refs(maint_client.rpc, audit_log_size)
      maint_client.rpc.nw_sync(ignore_locking_errors: true)
      sync_head_ref(maint_client.rpc, reader_rpc)
      sync_extra_state(maint_client.rpc, read_route)

      # This is just a minor hack for testing purposes, to give us somewhere
      # to simulate a concurrent push before the replica gets marked as OK.
      block.call if block_given?

      # Mark the cache replica as ok only if the repository checksum did not
      # change during the sync operation. If the checksum did change then it
      # means that there was a concurrent push and the replica will need to
      # be synced again.
      if !mark_ok_if_checksum_unchanged(repo.network.id, repo.id, repo_type, cache_host, synced_checksum)
        GitHub.logger.info("repository checksum changed during cache sync")
      end

      updated_refs.each { |update| deliver_cache_sync_event(repo.id, update, replica.fileserver.cache_location) }
    end
  rescue GitRPC::RepositoryOffline, GitRPC::NetworkError, GitRPC::NoDataError => e
    GitHub.logger.error("temporary error, trying again later", e)
  rescue => e # rubocop:todo Lint/GenericRescue
    GitHub.logger.error("failed repository sync", e)
    # If we get an unexpected exception it's possible that the cache
    # replica is corrupt.  Try to repair it.
    if maint_client && maint_client.rpc && replica_corrupt?(maint_client.rpc)
      res = restore_objects(maint_client.rpc)
      if res == :corrupt
        GitHub.logger.error("failed to restore objects, destroying network replica")
        SpokesDestroyNetworkReplicaJob.perform_now(repo.network.id, cache_host)
      end
    end

    raise
  ensure
    if start
      ms = (Time.now - start) * 1000
      GitHub.dogstats.distribution("dgit.actions.repair-repo.dist_time", ms, tags: ["server:#{cache_host}"])
    end
    maint_client.rpc.fs_unlock(lock_name) if our_lock
  end

  def deliver_cache_sync_event(repo_id, ref_update, cache_location)
    event = Hook::Event::CacheSyncEvent.new(
      action: :synced,
      repository_id: repo_id,
      cache_location: cache_location,
      ref_update: ref_update,
    )
    delivery_system = Hook::DeliverySystem.new(event)
    delivery_system.generate_hookshot_payloads
    delivery_system.deliver
  end

  def read_updated_refs(rpc, log_size_before)
    return [] unless rpc.fs_exist?("audit_log")
    contents = rpc.fs_read("audit_log", log_size_before)
    updates = contents.lines.map do |line|
      split = line.split(" ")
      { ref: split[0], before: split[1], after: split[2] }
    end
    updates.reject { |update| update[:ref].start_with?("refs/__gh__/") }
  end

  def replica_corrupt?(rpc)
    begin
      res = rpc.nw_fsck
      !res["ok"]
    rescue GitRPC::Protocol::DGit::ResponseError
      true
    end
  end

  def restore_objects(rpc)
    begin
      res = rpc.restore_objects(max: 10000)
      return :corrupt if !res["ok"]
      return :fixed if res["err"] =~ /object was restored/ || res["err"] =~ /objects were restored/
    rescue GitRPC::Protocol::DGit::ResponseError
      :corrupt
    end
  end

  def do_fetch(read_route, replica_rpc, host, repo_id, repo_type, is_wiki, start)
    # sync: use rpc to tell the broken replica to fetch git state from
    # the read-affinity replica.  Note that this will write the
    # updated refs to the audit_log.  In regular repairs we truncate
    # it, but here we keep it around so we have a log which refs are
    # updated during syncs.
    start = Time.now
    begin
      res = replica_rpc.fetch(read_route.remote_url, refspec: "+refs/*:refs/*", force: true, prune: true, dgit_disabled: true, committer_date: Time.current.to_formatted_s(:git))
    rescue GitRPC::CommandFailed => e
      raise GitHub::DGit::ReplicaSyncError, "Could not git fetch: #{e}"
    end
    GitHub.logger.info("git fetch succeeded.", "gh.process.stdout" => res["out"], "gh.process.stderr" => res["err"], "gh.timing.elapsed_seconds" => Time.now - start)
  end

  def sync_head_ref(replica_rpc, reader_rpc)
    refname = reader_rpc.symbolic_ref("HEAD")
    replica_rpc.update_symbolic_ref("HEAD", refname)
  end

  # Sync the config and info/nwo files
  def sync_extra_state(rpc, read_route)
    rsync_opts = { archive: true, verbose: true, hard_links: true,
                  delete: true, include: ["/info/", "/info/nwo", "config"],
                  exclude: ["*"], checksum: true }
    res = rpc.rsync(read_route.rsync_url, ".", rsync_opts)

    if !res["ok"]
      raise GitHub::DGit::ReplicaSyncError, "Could not rsync data: #{res["err"]}"
    end
  end

  # Mark the replica as OK if the repository checksum hasn't changed since the sync started.
  def mark_ok_if_checksum_unchanged(network_id, repo_id, repo_type, host, expected_checksum)
    db = GitHub::DGit::DB.for_network_id(network_id)

    ActiveRecord::Base.connected_to(role: :writing) do
      sql = db.SQL.new \
        network_id: network_id,
        repo_id: repo_id,
        repo_type: repo_type,
        host: host,
        checksum: expected_checksum
      sql.add <<-SQL
        UPDATE repository_replicas rr
        JOIN repository_checksums rc
        ON rr.repository_id = rc.repository_id
        AND rr.repository_type = rc.repository_type
        SET rr.updated_at = NOW(), rr.checksum = "ok"
        WHERE rr.repository_id = :repo_id
        AND rr.repository_type = :repo_type
        AND rr.host = :host
        AND rc.checksum = :checksum
      SQL

      sql.run.affected_rows > 0
    end
  end
end
