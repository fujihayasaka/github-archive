# typed: false
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesDestroyGistReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  def perform(gist_id, host, **opts)
    Failbot.push app: "github-dgit",
                 spec: "gist/#{gist_id}"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "gist/#{gist_id}") do
      GitHub.logger.info("start", "code.function" => "perform!")
      GitHub.dogstats.time("dgit.actions.destroy-gist", tags: ["server:#{host}"]) do
        perform!(gist_id, host)
      end
    end
  rescue Freno::Throttler::Error
  # Ignore freno errors and rely on retries from our own maintenance scheduler
  rescue GitHub::DGit::ReplicaDestroyNotFoundError
    # Ignore. This is possible due to races.
  end

  def perform!(gist_id, host, via: nil)
    Failbot.push(via: via) unless via.nil?

    gist = Gist.find_by_id(gist_id)
    raise GitHub::DGit::ReplicaDestroyNotFoundError, "There is no gist #{gist_id}" unless gist

    all_replicas = GitHub::DGit::Routing.all_gist_replicas(gist_id)
    Failbot.push delegate_replicas: all_replicas.inspect

    replica = all_replicas.find { |r| r.host == host }
    raise GitHub::DGit::ReplicaDestroyNotFoundError, "Gist #{gist_id} on #{host} not found" unless replica

    return unless GitHub::DGit::Maintenance.set_gist_state(gist_id, host, GitHub::DGit::DESTROYING)

    GitHub.stats.increment "dgit.#{host}.actions.destroy-gist" if GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["host:#{host}", "action:destroy", "type:gist"]

    GitHub::DGit::Maintenance::delete_gist_from_disk_on_replica(
      gist_id, replica, gist.original_shard_path)

    # Order for these next two steps is important.
    # - Deleting the gist_replicas row must be last, because its absence
    #   is what indicates that the destroy succeeded.  If it's still there as
    #   state=DESTROYING, then this operation will get retried as needed.
    # - Schedule the creation event before deleting the gist_replicas row,
    #   so that the creation event can avoid the host with to-be-deleted
    #   replica when picking a host on which to place the to-be-created
    #   replica.

    begin
      # Schedule creation of a replacement replica, if needed.
      remaining_replicas = GitHub::DGit::Routing.all_gist_replicas(gist_id).select(&:voting?).reject(&:destroying?)
    ensure
      # Delete the row from gist_replicas.
      GitHub::DGit::DB.for_gist_id(gist_id).throttle do
        GitHub::DGit::Maintenance.delete_gist_replica_for_host(gist_id, host)
      end
    end

    GitHub::DGit::Maintenance.rebalance_gist_read_weight(gist_id)
  end
end
