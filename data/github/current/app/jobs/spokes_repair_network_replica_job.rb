# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: false
# frozen_string_literal: true

require "set"

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"
require "github/dgit/routing"

class SpokesRepairNetworkReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  locked_by timeout: 2.hours, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  # Don't sync locks.
  EXCLUDE_RSYNC = [
    "/*/dgit-state.*",
    "/packed-refs.new",
    "*.lock",
    "/*/.backup_lock",
    "/*/objects/info/alternates+",
    "/*/objects/tmp_objdir-*",
    "/*/objects/ghq_*",
    "/*/objects/tmp_object_git2_*",
  ]

  # When syncing data with remote replicas, we need to account for reduced TCP throughput.
  #
  # Given 30 MiB/sec throughput, GitRPCs default 30 minute timeout would only allow us to copy ~50 GiB of data,
  # ignoring time spent on the sender side checksumming data.
  #
  # Bumping the timeout to two hours gives us an upper limit of 200 GiB, which - in combination with repo quotas of
  # 100 GiB - should serve us for some time.
  RSYNC_TIMEOUT = 2.hours

  # Try this many times -- repairing a network can fail if it
  # changes while the repair is taking place.  If after several
  # attempts, one or more repos in the network replica don't match
  # their expected checksums, trigger a destroy job.
  REPAIR_ATTEMPTS = 4

  resolve_tenant_context do |network_id|
    ::RepositoryNetworks::Public.resolve_tenant(id: network_id)
  end

  def perform(network_id, host)
    Failbot.push app: "github-dgit",
      spec: "network/#{network_id}"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "network/#{network_id}") do
      GitHub.logger.info("start", "code.function" => "perform!")
      GitHub.dogstats.time("dgit.actions.repair-network", tags: ["server:#{host}"]) do
        perform!(network_id, host, GitHub::DGit::FAILED, nil)
      end
    end
  rescue Freno::Throttler::Error
    # Ignore freno errors and rely on retries from our own maintenance scheduler
  end

  def network_replica_for_host(network_id, host)
    # Retry getting a network replica a few times, to make sure
    # the database has caught up.
    replica = nil
    (0..3).each do
      replica = GitHub::DGit::Routing.network_replica_for_host(network_id, host)
      break if replica
      GitHub.dogstats.increment("repair_network_replica.wait_for_replication.retry")
      sleep 5
    end
    raise GitHub::DGit::ReplicaRepairError, "Network #{network_id} on #{host} not found" unless replica
    replica
  end

  def perform!(network_id, host, prior_state, after_rsync = nil, strict = false)
    replica = network_replica_for_host(network_id, host)
    storage_path = GitHub::Routing.nw_storage_path(network_id: network_id)
    rpc = replica.to_route(storage_path).build_maint_rpc

    if replica.state != prior_state
      GitHub.logger.info("Repair of #{network_id} failed: expected state "\
        "#{GitHub::DGit::STATES[prior_state]} but got "\
        "#{GitHub::DGit::STATES[replica.state]}")
      return
    end

    begin
      read_route = choose_source(network_id, host)
    rescue GitHub::DGit::UnroutedError => e
      GitHub.logger.error({ :exception => e, "code.function" => "choose_source" })
      GitHub.logger.info("Repair of #{network_id} failed: unrouted (no available read replica)")

      # This is a tangly web, but by raising this exception rather than leaving
      # the replica as-is, callers of this job can set the state to something
      # more appropriate (like failed).
      raise GitHub::DGit::ReplicaRepairError.new("unrouted") unless prior_state == GitHub::DGit::FAILED
      return
    end

    # Only report this to statsd if we're performing a real
    # repair (which includes restoring a backup).  Don't tell
    # statsd about repairs that are due to replica creation and
    # replica migration (i.e., disk rebalancing).
    tell_statsd = (prior_state == GitHub::DGit::FAILED)
    GitHub.stats.increment "dgit.#{host}.actions.repair-network" if tell_statsd && GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["host:#{host}", "action:repair_network"]
    start = Time.now
    GitHub.logger.info("DGit repairing network replica #{network_id} on #{host} from source host #{read_route.original_host}",
      "gh.spokes.repairs.src_replica" => read_route.original_host)

    # Set the network replica to REPAIRING
    if !GitHub::DGit::Maintenance::set_network_state(network_id, host, GitHub::DGit::REPAIRING, prior_state)
      GitHub.logger.info("Repair of #{network_id} failed: could not change state "\
        "from #{GitHub::DGit::STATES[prior_state]} to REPAIRING")
      return
    end

    GitHub::DGit::Maintenance.backup_before_repair_with_rpc(rpc, self) unless prior_state == GitHub::DGit::CREATING

    (1..REPAIR_ATTEMPTS).each do |repair_attempt|
      begin
        GitHub.logger.info("Repair of network #{network_id} attempt: #{repair_attempt}")

        # hash repo_id -> type -> update time/checksum to examine after the rsync
        initial_checksums = checksums_for_network(network_id)
        if initial_checksums.empty?
          GitHub.logger.info("Repair of network #{network_id} skipped: network is empty")
          GitHub::DGit::Maintenance.set_network_state(
            network_id, host, GitHub::DGit::ACTIVE, GitHub::DGit::NOT_DORMANT)
          return
        end

        begin
          rpc.ensure_dir(rpc.backend.path)
        rescue GitRPC::CommandFailed => e
          Failbot.push mkdir_result: e
          raise GitHub::DGit::ReplicaRepairError, "Could not mkdir: #{e}"
        end

        begin
          noop = attempt_rsync(
            rpc, read_route.rsync_url,
            checksum: repair_attempt == 1,
            abbreviate_output: repair_attempt == 1,
            gitmon_models: repair_attempt == 1,
            reflogs: repair_attempt == 1
          )
        rescue GitRPC::Timeout => e
          # A client-side timeout may leave rsync running. We don't know
          # what state this replica is in and it will be changing. Best we
          # can do leave it "REPAIRING" and try again after the sweeper picks
          # up that this repair has been running too long and destroy it.
          GitHub.logger.error({ :exception => e, "code.function" => "attempt_rsync" })
          raise GitHub::DGit::ReplicaRepairFatalError, "Timeout waiting for rsync"
        end

        unless noop
          next
        end

        after_rsync.call if after_rsync

        if confirm_repair(network_id, host, rpc, initial_checksums, strict)
          GitHub.logger.info("DGit completed repair for network #{network_id} on #{host}",
            "gh.timing.elapsed_seconds" => Time.now - start,
            "gh.spokes.replica_state" => "ACTIVE")
          return GitHub::DGit::Maintenance.set_network_state(
            network_id, host, GitHub::DGit::ACTIVE, GitHub::DGit::NOT_DORMANT)
        end
      rescue ActiveRecord::QueryCanceled => e
        # Some queries struggle with large networks. Better to retry now
        # rather than fail only to create a new replica from scratch hours
        # later.
        # This should be true of almost any exception generated post-rsync.
        Failbot.report(e)
      rescue GitHub::DGit::ReplicaRepairError => e
        Failbot.report(e)
      end
    end

    GitHub.logger.info("Repair unsuccessful after #{REPAIR_ATTEMPTS} attempts",
      "gh.timing.elapsed_seconds" => Time.now - start,
      "gh.spokes.repair_attempts" => REPAIR_ATTEMPTS,
      "gh.spokes.replica_state" => "FAILED")

    # Don't destroy the network.  Try again in two minutes.
    # FIXME: this will retry indefinitely.
    GitHub::DGit::Maintenance.set_network_state(
      network_id, host, GitHub::DGit::FAILED, GitHub::DGit::NOT_DORMANT)
    nil
  end

  private

  def attempt_rsync(rpc, rsync_url, checksum:, abbreviate_output:, gitmon_models:, reflogs:)
    additional_exclude = []
    if !gitmon_models
      additional_exclude << "/gitmon.model"
      additional_exclude << "/*/gitmon.model"
      additional_exclude << "/governor.model"
      additional_exclude << "/*/governor.model"
    end

    if GitHub.flipper[:network_repair_skip_reflog_on_retry].enabled?
      if !reflogs
        additional_exclude << "/logs/*"
        additional_exclude << "/*/logs/*"
      end
    end

    noop0 = rsync(
      rpc, rsync_url, ".", EXCLUDE_RSYNC + ["/network.git"] + additional_exclude,
      checksum: checksum, abbreviate_output: abbreviate_output
    )

    # We use ignore_missing here because we don't mind if network.git doesn't
    # exist on the source. That should just mean that we're dealing with a
    # standalone repository.
    noop1 = rsync(
      rpc, "#{rsync_url}/network.git", ".",
      EXCLUDE_RSYNC + additional_exclude,
      checksum: checksum,
      abbreviate_output: abbreviate_output,
      ignore_missing: true
    )

    noop0 && noop1
  end

  def rsync(rpc, src, dst, exclude, checksum:, abbreviate_output:, ignore_missing: false)
    rsync_opts = {
      archive: true,
      verbose: true,
      hard_links: true,
      delete: true,
      stats: true,
      exclude: exclude,
      ignore_missing: ignore_missing
    }

    # Use --checksum to find files with matching mtime and size.
    # Only necessary on the first pass -- passes 2+ only exist to
    # pick up files that have changed, which will have new mtimes.
    rsync_opts[:checksum] = true if checksum

    GitHub.logger.info("rsync beginning: #{src}")
    res = rpc.with_timeout(RSYNC_TIMEOUT) do
      rpc.rsync(src, dst, rsync_opts)
    end
    if !res["ok"]
      if GitHub::DGit::RETRYABLE_RSYNC_RESULTS.include?(res["status"])
        GitHub.logger.info("rsync failed with #{res["status"]} (retryable): #{src}")
        return false
      else
        GitHub.logger.error("rsync failed with #{res["status"]}: #{src}")
        Failbot.push rsync_result: res
        raise GitHub::DGit::ReplicaRepairError, "Could not rsync: #{res["err"]}"
      end
    end

    if abbreviate_output
      GitHub.logger.info("rsync succeeded: #{src} (#{res["out"].lines.size} lines of output)",
                         "gh.process.stderr" => res["err"]&.gsub(/\n/, "\\n"))
    else
      GitHub.logger.info("rsync succeeded: #{src}",
                         "gh.process.stdout" => res["out"]&.gsub(/\n/, "\\n"),
                         "gh.process.stderr" => res["err"]&.gsub(/\n/, "\\n"))
    end

    # rsync transfers 0 files and 0 bytes when it's done
    noop   = (res["out"] =~ /Number of (?:regular )?files transferred: 0/)
    noop &&= (res["out"] =~ /Total transferred file size: 0 bytes/)
    # rsync isn't done if it created or deleted any files
    noop &&= (res["out"] !~ /Number of created files: [^0]/)
    noop &&= (res["out"] !~ /^deleting\s/)

    noop
  end

  # If the checksum for the specified [repo_id, repo_type] is
  # valid and unanimous on the other replicas, and hasn't changed
  # since initial_replicas, return it. Otherwise, return nil.
  # Note: `initial_replicas` and `current_replicas` are maps
  #
  #     {host => {checksum: checksum, updated_at: time}}
  def known_checksum(host, repo_id, repo_type, initial_replicas, current_replicas)
    other_replicas = current_replicas.except(host)

    # ensure that fork update times and checksums did not change
    # during the rsync
    return if other_replicas != initial_replicas.except(host)

    # ensure that all checksums are identical and valid (ie, not "creating")
    uniq_checksums = other_replicas.collect { |_k, v| v[:checksum] }.uniq
    return if uniq_checksums.length != 1

    checksum = uniq_checksums.first
    return if checksum == "creating"

    checksum
  end

  # Recompute and update the checksums for the specified
  # repository and its wiki (if present). Return the number of
  # checksums that still have to be considered bad.
  def update_checksums_for_network_replica_repair(host, network_id, repo_id)
    repo = Repository.find_by_id(repo_id)
    if !repo
      # skip just-now-deleted repos, but count them as problems
      GitHub.logger.info("cannot update checksum as repo does not exist", "gh.repo.id" => repo_id)
      return 1
    end

    checksum = GitHub::DGit::Routing.repo_checksum(network_id, repo_id)
    if checksum == "creating" || checksum == "" || checksum.nil?
      # If this repo hasn't even been created then there is nothing to
      # repair. Counting these as bad_checksums would likely cause our network
      # replica to be stuck in a unrepairable state. This condition should be
      # fixed up by SpokesRepairDoaRepo job.
      GitHub.logger.info("no checksum update because there is no checksum", "gh.spokes.spec" => "#{network_id}/#{repo_id}", "gh.spokes.is_doa" => true)
      return 0
    end

    # Count up how many bad checksums we see, this can be more than 1
    # because of wikis.
    bad_checksums = 0

    # Can't just use `read_route.host`, because we need to bless a
    # repo with a healthy checksum.
    repo_read_host = GitHub::DGit::Routing.hosts_for_repo(repo_id).first
    if !repo_read_host
      GitHub.logger.info("no read routes found for repo", "gh.spokes.spec" => repo.dgit_spec, "gh.spokes.is_unrouted" => true)
      bad_checksums += 1
    end

    if repo.unsullied_wiki.exist?
      # Because the best wiki replica might be on a different host to the
      # best repo replica, make a separate decision for any wiki that needs
      # repairing.  Don't simply reuse `repo_read_host`.
      wiki_read_host = GitHub::DGit::Routing.hosts_for_repo(repo_id, true).first
      if !wiki_read_host
        GitHub.logger.info("no read routes found for wiki", "gh.spokes.spec" => repo.dgit_spec(wiki: true), "gh.spokes.is_unrouted" => true)
        bad_checksums += 1
      end
    else
      wiki_read_host = nil
    end

    begin
      GitHub::DGit::DB.for_network_id(network_id).throttle do
        if repo_read_host
          if !attempt_recompute_checksums(network_id, repo, repo_read_host, host, :repo)
            bad_checksums += 1
          end
        end

        if wiki_read_host
          if !attempt_recompute_checksums(network_id, repo, wiki_read_host, host, :wiki)
            bad_checksums += 1
          end
        end
      end
    rescue Freno::Throttler::ClientError => e
      GitHub.logger.error(
        { :exception => e, "log_message" => "failed to recompute checksum due to freno failure", "gh.spokes.spec" => repo.dgit_spec })

      # Presumably the checksum was not updated so assume it's still bad.
      bad_checksums += 1
    end

    bad_checksums
  end

  def attempt_recompute_checksums(network_id, repo, good_host, repair_host, repo_type)
    begin
      checksum_result = GitHub::DGit::Maintenance.recompute_checksums(
        repo, good_host, is_wiki: repo_type == :wiki, vote_fallback: true)
      repair_replica = GitHub::DGit::Routing.repo_replica_for_host(repo.id, repair_host)
      unless repair_replica.checksum_ok?
        GitHub.logger.info("#{repo.dgit_spec(wiki: repo_type == :wiki)} has mismatched checksum on #{repair_host}: "\
          "checksum = #{repair_replica.checksum}, "\
          "expected_checksum = #{repair_replica.expected_checksum}")
        return false
      end
    rescue GitHub::DGit::Error => e
      Failbot.report(e, spec: repo.dgit_spec(wiki: repo_type == :wiki), app: "github-dgit-debug")
      GitHub.logger.error({ :exception => e, "code.namespace" => "GitHub::DGit::Maintenance", "code.function" => "recompute_checksums" })
      return false
    end
    true
  end

  def choose_source(network_id, dest_host)
    storage_path = GitHub::Routing.nw_storage_path(network_id: network_id)
    delegate = GitHub::DGit::Delegate::Network.new(network_id, storage_path)

    delegate.get_read_routes.find(-> { raise GitHub::DGit::UnroutedError }) do |r|
      valid_source(r, dest_host)
    end
  end

  def valid_source(route, dest_host)
    return false if route.original_host == dest_host

    rpc = route.build_maint_rpc

    # Confirm the potential source at least has some repositories on disk.
    # While this isn't very rigorous (are the repositories up-to-date? Complete
    # broken?) it's better than simply assuming any ACTIVE replica is ok to use.
    # NOTE: Looking for `config` because it matches what rpc.exist? looks for.
    begin
      return false if rpc.forks_with_file("config").empty?
    rescue ::GitRPC::InvalidRepository
      # This seems to be the error we get when the path for the network doesn't even exist.
      return false
    end

    true
  end

  def confirm_repair(network_id, host, rpc, initial_checksums, strict = false)
    # All the new repository replicas need checksums. Ideally we can avoid
    # recalculating them by comparing the current checksums in the DB to the
    # ones we initially read. But if they've changed we'll need to recompute
    # them.
    current_checksums = checksums_for_network(network_id)
    updated_checksums = Hash.new

    repositories_to_checksum = Set.new

    # While we hope to skip directly checking the checksums for the repositories
    # we do need to ensure they have a repository on disk. If the dgit-state
    # file is missing that would indicate we either don't have a repository or
    # it's currently in 3PC transaction.
    dgit_states = Set.new
    rpc.forks_with_file("dgit-state").each do |dir|
      if dir =~ /\A(\d+)(\.wiki)?\.git\z/
        dgit_states.add [$1.to_i, $2.nil? ? GitHub::DGit::RepoType::REPO : GitHub::DGit::RepoType::WIKI]
      end
    end

    current_checksums.each do |(repo_id, repo_type), current_replicas|
      # if we didn't see the dgit-state in the source, we cannot
      # do the quick update, do a full checksum recomputation
      checksum = dgit_states.include?([repo_id, repo_type]) &&
        known_checksum(host, repo_id, repo_type,
                        initial_checksums[[repo_id, repo_type]],
                        current_replicas)
      if checksum
        updated_checksums[[repo_id, repo_type]] = checksum
      else
        repositories_to_checksum.add(repo_id)
      end
    end

    GitHub::DGit::RepoType::REPO_ISH.each do |repo_type|
      checksums_for_type = updated_checksums.filter_map { |(id, t), cs| [id, cs] if t == repo_type }

      GitHub.logger.info("updating #{checksums_for_type.size} #{GitHub::DGit::RepoType::REPO_TYPES[repo_type]} replica checksums")
      checksums_for_type.each_slice(100) do |update_slice|
        GitHub::DGit::Delegate.update_checksums_for_host(network_id, host, repo_type, Hash[update_slice])
      end
    end

    GitHub.logger.info("Recomputing checksums on #{repositories_to_checksum.size} forks")

    bad_checksums = 0
    repositories_to_checksum.each_with_index do |repo_id, idx|
      if idx % 100 == 0
        GitHub.logger.info("[#{idx + 1}/#{repositories_to_checksum.size}] #{repo_id}")
      end

      bad_checksums += update_checksums_for_network_replica_repair(host, network_id, repo_id)
    end

    GitHub.logger.info("confirming repair",
      "gh.spokes.repairs.num_network_checksums" => current_checksums.size,
      "gh.spokes.repairs.num_repos" => repositories_to_checksum.size,
      "gh.spokes.repairs.bad_checksums" => bad_checksums)

    if strict
      bad_checksums == 0
    else
      # 100% success isn't necessary to call this network repair a success. If a
      # few repositories in a large network are still out of date they will be
      # better handled by a repo repair job.
      #
      # NOTE: busy repositories may never succeed as this job has no ability to
      # lock writes.  If that busy repository is in a small network, this job may
      # never succceed.
      bad_checksums < 1000 && bad_checksums <= current_checksums.size / 3
    end
  end

  def checksums_for_network(network_id)
    checksums = {}

    GitHub::DGit::Util.network_replicas(network_id).each do |network_replica_id, host, _|
      GitHub::DGit::Util.each_repository_replica_for_network_replica(network_id, network_replica_id) do |repo_id, repo_type, updated_at, checksum|
        checksums[[repo_id, repo_type]] ||= {}
        checksums[[repo_id, repo_type]][host] = { updated_at: updated_at, checksum: checksum }
      end
    end

    checksums
  end
end
