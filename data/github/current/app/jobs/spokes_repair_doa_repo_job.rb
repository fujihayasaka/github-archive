# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"
require "github/dgit/util"

# Complete the initialization of a repo that got stuck in `creating`
# state, by calculating the checksums on all replicas and picking the
# majority.  Absent a majority, we pick the replica that looks most
# fully initialized.
class SpokesRepairDoaRepoJob < ApplicationJob
  queue_as :dgit_repairs

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  resolve_tenant_context do |repo_id|
    Repositories::Public.resolve_tenant(id: repo_id)
  end

  def perform(repo_id, is_wiki = false)
    Failbot.push app: "github-dgit"

    repo = Repository.find_by_id(repo_id)
    raise GitHub::DGit::ReplicaRepairError, "Replica #{repo_id} not found" unless repo

    Failbot.push spec: repo.dgit_spec(wiki: is_wiki)

    GitHub.logger.with_named_tags("gh.spokes.spec" => repo.dgit_spec(wiki: is_wiki)) do
      GitHub.logger.info("start", "code.function" => "perform!")
      GitHub.dogstats.time "dgit.actions.repair-doa-repo" do
        perform!(repo_id, is_wiki)
      end
    end
  rescue Freno::Throttler::Error
  end

  def perform!(repo_id, is_wiki = false)
    repo = Repository.find_by_id(repo_id)
    raise GitHub::DGit::ReplicaRepairError, "Replica #{repo_id} not found" unless repo

    # The first thing to do is transactionally confirm this is a valid DOA and
    # remove the checksum row which will prevent races with any 3pc
    # transactions.
    GitHub::DGit::Maintenance.reset_if_doa_repo(repo.network.id, repo.id, is_wiki)

    # A checksum at this point indicates we weren't DOA.
    checksum = if is_wiki
      GitHub::DGit::Routing.wiki_checksum(repo.network.id, repo_id)
    else
      GitHub::DGit::Routing.repo_checksum(repo.network.id, repo_id)
    end

    if checksum
      GitHub.logger.info("skipping repair: not DOA",
        "gh.spokes.is_doa" => false,
        "gh.spokes.repo_checksum" => checksum)
      return
    end

    # log the action
    GitHub.stats.increment "dgit.nohost.actions.repair-doa-repo" if GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["type:nohost", "action:repair_doa_repo"]

    repo_type = is_wiki ? GitHub::DGit::RepoType::WIKI : GitHub::DGit::RepoType::REPO

    # Only create new network replicas if there are none.  This does potentially
    # leave the repository under-replicated scenario if the network replicas are
    # also incomplete.
    no_network_replicas = GitHub::DGit::Routing.all_network_replicas(repo.network.id).empty?
    repo.network.initialize_placeholder_network_replicas if no_network_replicas

    # This is a destructive call that will delete any existing replicas and
    # checksums. But we've already confirmed this is DOA so it's safe.
    GitHub::DGit::Maintenance.insert_placeholder_replicas_and_checksums(repo_type, repo.id, repo.network.id)

    # XXX - how should this behave w.r.t. voting vs non-voting replicas?
    #       in other words, should non-voting replicas be allowed to define the
    #       best checksum?
    replicas = GitHub::DGit::Routing.all_repo_replicas(repo_id, is_wiki).select(&:active?)

    rpc_map = {}
    replicas.each do |r|
      rpc = if is_wiki
        r.to_route(repo.wiki_shard_path).build_maint_rpc
      else
        r.to_route(repo.original_shard_path).build_maint_rpc
      end
      rpc_map[r] = rpc
    end

    no_replicas_exist = !replicas.map { |r| rpc_map[r].exist? }.any?

    GitHub.logger.info("fetched state of replicas",
      "gh.spokes.num_replicas" => replicas.size,
      "gh.spokes.has_replicas" => no_replicas_exist,
      "gh.spokes.has_network_replicas" => no_network_replicas)

    if no_replicas_exist
      if is_wiki
        repo.unsullied_wiki.create_git_repository_on_disk
      else
        repair_repository(repo)
      end
    else
      replicas.each do |r|
        GitHub::DGit::Maintenance.backup_before_repair_with_rpc(rpc_map[r], self)
      end

      host_checksums = GitHub::DGit::Maintenance.recompute_checksums(repo, nil, is_wiki: is_wiki)

      # This is legacy behaviour that should be removed in the future. It assumes that we can just choose our own
      # "best checksum" and write that to the database as the correct one. That no longer holds true because the
      # checksum in the database is no longer treated as authoritative. Instead, we should just let
      # recompute_checksums write the majority checksum and avoid overwriting it.
      best_checksum = GitHub::DGit::Util.get_majority(host_checksums) ||
        host_checksums[get_most_complete(repo.dgit_spec(wiki: is_wiki), replicas, rpc_map)]
      GitHub.logger.info("fetched checksums", "gh.spokes.replica_checksums" => host_checksums.inspect, "gh.spokes.majority_checksum" => best_checksum)

      GitHub::DGit::Delegate.update_checksums(
        repo.network.id,
        repo.id,
        is_wiki,
        host_checksums.transform_values { |checksum| checksum == best_checksum ? "ok" : "bad" },
        best_checksum)
    end

    true
  end

  # Returns the name of the host with the most complete repo.
  # XXX: Consider batching these calls into a single API?
  #  - replicas = an array of repo or wiki replicas
  #  - rpc_map      = map from replica to its RPC handle
  def get_most_complete(spec, replicas, rpc_map)
    scores = replicas.map do |replica|
      score = 0
      r = rpc_map[replica]
      begin
        if r.fs_exist?("HEAD")
          score += 1
          score += 1 if r.fs_read("HEAD").length > 0
        end
        if r.fs_exist?("config")
          score += 1
          score += 1 if r.config_get("core.dgit")
        end
        if r.fs_exist?("info/nwo")
          score += 1
          score += 1 if r.fs_read("info/nwo").length > 0
        end
        score += 1 if r.fs_exist?("audit_log")
      rescue GitRPC::Error
      end
      [replica.host, score]
    end.sort_by { |x| -x[1] }

    if scores[0][1] < 4
      raise GitHub::DGit::ReplicaRepairError, "Repo #{spec} has no good-enough replicas: #{scores}"
    end
    scores[0][0]
  end

  def repair_repository(repo)
    if repo.fork?
      return if repo.exists_on_disk?
      return if repo.owner.nil?

      repo.clone_fork

      return
    end

    with_write { repo.setup_git_repository }
  end
end
