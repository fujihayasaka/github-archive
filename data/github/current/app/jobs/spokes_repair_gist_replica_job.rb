# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

# Using `rsync`, bring a given gist replica back into compliance with
# other replicas for that gist.
class SpokesRepairGistReplicaJob < ApplicationJob
  queue_as :dgit_repairs
  # Don't sync locks or git state with rsync.  Git state syncs better with git.
  EXCLUDE_RSYNC = [
    "/dgit-state*",
    "/packed-refs.new",
    "*.lock",
    "/.backup_lock",
    "/objects/info/alternates+",
  ]
  REPAIR_ATTEMPTS = 4

  def perform(gist_id, host)
    Failbot.push spec: "gist/#{gist_id}",
      app: "github-dgit"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "gist/#{gist_id}") do
      GitHub.logger.info("start", "code.function" => "perform!")
      GitHub.dogstats.time("dgit.actions.repair-gist", tags: ["server:#{host}"]) do
        perform!(gist_id, host, false)
      end
    end
  rescue Freno::Throttler::Error
    # Ignore freno errors and rely on retries from our own maintenance scheduler
  end

  def gist_replica_for_host(gist_id, host)
    # Retry getting a network replica a few times, to make sure
    # the database has caught up.
    gr = nil
    4.times do
      gr = GitHub::DGit::Routing.gist_replica_for_host(gist_id, host)
      break if gr
      GitHub.dogstats.increment("repair_gist_replica.wait_for_replication.retry")
      sleep 5 unless Rails.env.test?
    end
    raise GitHub::DGit::ReplicaRepairError, "Replica gist #{gist_id} on #{host} not found" unless gr
    gr
  end

  def perform!(gist_id, host, is_creating = false, via: nil)
    gr = gist_replica_for_host(gist_id, host)
    desc = (is_creating ? "Create" : "Repair")
    gist = Gist.find_by_id(gist_id)

    if [GitHub::DGit::Routing.gist_checksum(gist_id), "ok"].include?(gr.checksum) && gr.active?
      GitHub.logger.info("skipping #{desc}: replica ok",
        "gh.spokes.is_repair_needed" => false,
        "gh.spokes.replica_checksum" => gr.checksum)
      return
    end

    if is_creating && (gr.state != GitHub::DGit::CREATING)
      GitHub.logger.info("#{desc} failed: expected state #{GitHub::DGit::STATES[GitHub::DGit::CREATING]}",
        "gh.spokes.is_unexpected_replica_state" => true,
        "gh.spokes.replica_state" => GitHub::DGit::STATES[gr.state])
      return
    end

    # Obtain a read route for a non-evacuating host to use for a repair.
    # If repairs are attempted from a donor host that is currently being
    # evacuated, the underlying disk contents may be removed out from
    # under us mid-repair.  Try to avoid that.
    begin
      read_route = nil
      gist.dgit_read_routes.each do |r|
        if (r.host != host) && !GitHub::DGit::Util.is_evacuating?(r.host)
          read_route = r
          break
        end
      end

      # Couldn't find a route on a non-evacuating host:
      # fall back to using the first read route.
      if read_route.nil?
        read_route = gist.dgit_read_routes.first
      end
    rescue GitHub::DGit::UnroutedError => e
      GitHub.logger.error({ :exception => e, "code.namespace" => "Gist::DGit", "code.function" => "dgit_read_routes" })
      return
    end

    if read_route.original_host == host
      raise GitHub::DGit::ReplicaRepairError,
        "Cannot #{desc.downcase} gist #{gist_id} on #{host} from itself"
    end

    #
    # First recompute checksums for the case that the replica already exists
    # and has not transitioned to FAILED.  If the refreshed replica checksum
    # matches the record in the database, ensure this replica is toggled
    # ACTIVE and return early.
    #
    unless is_creating || (gr.state == GitHub::DGit::FAILED)
      host_checksums = GitHub::DGit::Maintenance.recompute_gist_checksums(
        gist, read_route.original_host, host_to_activate: host)
      if host_checksums[:checksum] == host_checksums[host]
        GitHub.logger.info("DGit completed #{desc.downcase} by refreshing checkums", "gh.spokes.is_repair_needed" => false)
        return true
      end
    end

    #
    # Refreshing checksums alone didn't work, or, this is a new creation:
    # actually perform a repair.
    #
    tell_statsd = !is_creating
    GitHub.stats.increment "dgit.#{host}.actions.repair-gist" if tell_statsd && GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["action:repair_gist", "host:#{host}"]
    GitHub.logger.info("start #{desc.downcase}",
                       "gh.spokes.is_replica_creating" => is_creating,
                       "gh.spokes.repairs.src_replica" => read_route.original_host,
                       "gh.spokes.repairs.via" => via)
    GitHub::DGit::Maintenance.set_gist_state(gist_id, host, GitHub::DGit::REPAIRING) unless is_creating

    rpc = gr.to_route(gist.original_shard_path).build_maint_rpc
    GitHub::DGit::Maintenance.backup_before_repair_with_rpc(rpc, self) unless is_creating

    (1..REPAIR_ATTEMPTS).each do |repair_attempt|
      if is_creating || (gr.state == GitHub::DGit::FAILED)
        begin
          rpc.ensure_dir(rpc.backend.path)
        rescue GitRPC::CommandFailed => e
          GitHub.logger.error({ :exception => e, "method" => "ensure_dir" })
          raise GitHub::DGit::ReplicaRepairError, "Could not mkdir: #{e}"
        end
      else
        raise ::GitRPC::InvalidRepository unless rpc.exist?
      end

      rsync_opts = { archive: true, verbose: true, hard_links: true,
                    delete: true, stats: true, exclude: EXCLUDE_RSYNC }

      # Use --checksum to find files with matching mtime and size.
      # Only necessary on the first pass -- passes 2+ only exist to
      # pick up files that have changed, which will have new mtimes.
      rsync_opts[:checksum] = true if repair_attempt == 1

      GitHub.logger.info("rsync beginning.")
      begin
        res = rpc.rsync(read_route.rsync_url, ".", rsync_opts)
      rescue GitRPC::Timeout => e
        # A client-side timeout may leave rsync running. We don't know
        # what state this replica is in and it will be changing. Best we
        # can do leave it "REPAIRING" and try again after the sweeper picks
        # up that this repair has been running too long and destroy it.
        GitHub.logger.error({ :exception => e, "method" => "rsync" })
        raise GitHub::DGit::ReplicaRepairFatalError, "Timeout waiting for rsync"
      end

      unless res["ok"]
        raise GitHub::DGit::ReplicaRepairError, "Could not rsync"
      end

      log_data = emit_rsync_stats_and_log_data(res["out"])
      log_data["gh.spokes.repairs.rsync.num_lines_stdout"] = res["out"].lines.size
      log_data["gh.spokes.repairs.repair_attempt"] = repair_attempt

      if repair_attempt != 1
        log_data["gh.spokes.repairs.rsync.stdout"] = res["out"]
        log_data["gh.spokes.repairs.rsync.stderr"] = res["err"]
      end
      GitHub.logger.info("rsync succeeded", log_data)

      next unless (res["out"] =~ /Number of (?:created files|files transferred): 0/) && (res["out"] =~ /Total transferred file size: 0 bytes/)

      GitHub::DGit::DB.for_gist_id(gist.id).throttle do
        host_checksums = GitHub::DGit::Maintenance.recompute_gist_checksums(
          gist, read_route.original_host, host_to_activate: host)
      end
      ok = (host_checksums[:checksum] == host_checksums[host])
      if !ok
        GitHub.logger.info("mismatched checksum on #{host}: want " \
          "#{host_checksums[:checksum]} but got #{host_checksums[host]}")
      else
        GitHub.logger.info("DGit completed #{desc.downcase}. Returning OK")
        return true
      end
    end

    GitHub.logger.info("#{desc} unsuccessful after #{REPAIR_ATTEMPTS} attempts")
    GitHub::DGit::Maintenance::set_gist_state(gist_id, host, GitHub::DGit::FAILED)
    nil
  rescue GitHub::DGit::ReplicaRepairError, ::GitRPC::Error => e
    GitHub::DGit::Maintenance::set_gist_state(gist_id, host, GitHub::DGit::FAILED)
    raise e
  end

  private

  # emit any non-zero values to metrics and return a hash of data for logs
  # regardless of values
  def emit_rsync_stats_and_log_data(rsync_output)
    log_data = {}

    rsync_output.match /^Number of files: (.+) \(.+\)$/ do |num_files_match|
      num_files = num_files_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.num_files", num_files) unless num_files == 0
      log_data["gh.spokes.repairs.rsync.num_files"] = num_files
    end

    rsync_output.match /^Number of created files: (.+) \(.+\)$/ do |num_created_files_match|
      num_created_files = num_created_files_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.num_created_files", num_created_files) unless num_created_files == 0
      log_data["gh.spokes.repairs.rsync.num_created_files"] = num_created_files
    end

    rsync_output.match /^Number of deleted files: (.+) \(.+\)$/ do |num_deleted_files_match|
      num_deleted_files = num_deleted_files_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.num_deleted_files", num_deleted_files) unless num_deleted_files == 0
      log_data["gh.spokes.repairs.rsync.num_deleted_files"] = num_deleted_files
    end

    rsync_output.match /^Number of regular files transferred: (.+)$/ do |num_transferred_files_match|
      num_transferred_files = num_transferred_files_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.num_transferred_files", num_transferred_files) unless num_transferred_files == 0
      log_data["gh.spokes.repairs.rsync.num_transferred_files"] = num_transferred_files
    end

    rsync_output.match /^Total file size: (.+) bytes$/ do |total_file_size_match|
      total_file_size = total_file_size_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.total_file_size", total_file_size) unless total_file_size == 0
      log_data["gh.spokes.repairs.rsync.total_file_size"] = total_file_size
    end

    rsync_output.match /^Total transferred file size: (.+) bytes$/ do |transferred_file_size_match|
      transferred_file_size = transferred_file_size_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.transferred_file_size", transferred_file_size) unless transferred_file_size == 0
      log_data["gh.spokes.repairs.rsync.transferred_file_size"] = transferred_file_size
    end

    rsync_output.match /^File list size: (.+)$/ do |file_list_size_match|
      file_list_size = file_list_size_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.file_list_size", file_list_size) unless file_list_size == 0
      log_data["gh.spokes.repairs.rsync.file_list_size"] = file_list_size
    end

    rsync_output.match /^Total bytes sent: (.+)$/ do |total_bytes_sent_match|
      total_bytes_sent = total_bytes_sent_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.total_bytes_sent", total_bytes_sent) unless total_bytes_sent == 0
      log_data["gh.spokes.repairs.rsync.total_bytes_sent"] = total_bytes_sent
    end

    rsync_output.match /^Total bytes received: (.+)$/ do |total_bytes_received_match|
      total_bytes_received = total_bytes_received_match[1].delete(",").to_i
      GitHub.dogstats.distribution("repair_gist_replica.rsync.total_bytes_received", total_bytes_received) unless total_bytes_received == 0
      log_data["gh.spokes.repairs.rsync.total_bytes_received"] = total_bytes_received
    end

    log_data
  end
end
