# typed: true
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesMoveGistReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  def perform(gist_id, from_host, to_host, queued_time = nil)
    Failbot.push spec: "gist/#{gist_id}",
                 app: "github-dgit"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "gist/#{gist_id}") do
      GitHub.logger.info("start", "code.function" => "perform!", "gh.spokes.repairs.src_replica" => from_host)
      perform!(gist_id, from_host, to_host, queued_time)
    end
  rescue Freno::Throttler::Error
  # Ignore freno errors and rely on retries from our own maintenance scheduler
  rescue GitHub::DGit::ReplicaDestroyNotFoundError
    # Ignore. This is possible due to races.
  end

  def perform!(gist_id, from_host, to_host, queued_time = nil)
    raise GitHub::DGit::ReplicaMoveError, "Source and destination are both #{from_host}" if from_host == to_host

    # If a gist was replicated to another host after this time,
    # don't raise; assume another move job was scheduled before us.
    # Use either the time this job was queued (plus a fudge factor of
    # one minute) or an hour ago, if no time was specified.
    fail_time = queued_time ? Time.at(queued_time) - 1.minute : Time.now - 1.hour

    # See where we're currently replicated and check that there is a
    # replica on `from_host`. The destroy job will also do this, but
    # we want to do it early so we can fail before going through
    # with the create job.
    replicas = GitHub::DGit::Routing.all_gist_replicas(gist_id)
    Failbot.push delegate_replicas: replicas.inspect

    unless replicas.any? { |r| r.host == from_host }
      return if replicas.any? { |r| r.created_at > fail_time }
      raise GitHub::DGit::ReplicaDestroyNotFoundError, "Gist #{gist_id} on #{from_host} not found"
    end

    GitHub.logger.info("start", "code.namespace" => "SpokesCreateGistReplicaJob", "code.function" => "perform!")
    SpokesCreateGistReplicaJob.new.perform!(gist_id, to_host, via: :dgit_move_gist_replica)

    GitHub.logger.info("start", "code.namespace" => "SpokesDestroyGistReplicaJob", "code.function" => "perform!")
    # Inhibit repairs to avoid having the destroy job try to create any new replicas. We just created one.
    SpokesDestroyGistReplicaJob.new.perform!(gist_id, from_host, via: :dgit_move_gist_replica)
  end
end
