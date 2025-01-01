# typed: true
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesMoveNetworkReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  def perform(network_id, from_host, to_host, queued_time = nil, after_rsync = nil)
    Failbot.push app: "github-dgit",
      spec: "network/#{network_id}"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "network/#{network_id}") do
      GitHub.logger.info("start", "code.function" => "perform!", "gh.spokes.repairs.src_replica" => from_host)
      perform!(network_id, from_host, to_host, queued_time, after_rsync)
    end
  rescue Freno::Throttler::Error
    # Ignore freno errors and rely on retries from our own maintenance scheduler
  rescue GitHub::DGit::ReplicaDestroyNotFoundError
    # Ignore. This is possible due to races.
  end

  def perform!(network_id, from_host, to_host, queued_time = nil, after_rsync = nil)
    raise GitHub::DGit::ReplicaMoveError, "Source and destination are both #{from_host}" if from_host == to_host

    # If a network was replicated to another host after this time,
    # don't raise; assume another move job was scheduled before us.
    # Use either the time this job was queued (plus a fudge factor of
    # one minute) or an hour ago, if no time was specified.
    fail_time = queued_time ? Time.at(queued_time) - 1.minute : Time.now - 1.hour

    # See where we're currently replicated and check that the replica
    # is actually on `from_host`. The destroy job will also do this,
    # but we want to do it early so we can fail before going through
    # with the create job.
    replicas = GitHub::DGit::Routing.all_network_replicas(network_id)

    unless replicas.any? { |r| r.host == from_host }
      return if replicas.any? { |r| r.created_at > fail_time }
      raise GitHub::DGit::ReplicaDestroyNotFoundError, "Network #{network_id} on #{from_host} not found"
    end

    GitHub.logger.info("start", "code.namespace" => "SpokesCreateNetworkReplicaJob", "code.function" => "perform!")
    SpokesCreateNetworkReplicaJob.new.perform!(network_id, to_host, after_rsync, true)

    replica = with_write do
      GitHub::DGit::Routing.network_replica_for_host(network_id, to_host)
    end
    raise GitHub::DGit::ReplicaMoveError, "Could not create destination #{to_host}" if replica.nil?
    GitHub.logger.info("skipping deletion", "code.namespace" => "SpokesCreateNetworkReplicaJob", "code.function" => "perform!") if !replica.active?

    GitHub::DGit::Maintenance.destroy_network_replica(network_id, from_host) if replica.active?
  end
end
