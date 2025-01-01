# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

require "github/dgit/delegate"
require "github/dgit/error"
require "github/dgit/maintenance"

class SpokesCreateGistReplicaJob < ApplicationJob
  queue_as :dgit_repairs

  def perform(gist_id, host)
    Failbot.push app: "github-dgit",
                 spec: "gist/#{gist_id}"

    GitHub.logger.with_named_tags("gh.spokes.spec" => "gist/#{gist_id}") do
      GitHub.logger.info("start", "code.function" => "perform!")
      GitHub.dogstats.time("dgit.actions.create-gist", tags: ["server:#{host}"]) do
        perform!(gist_id, host)
      end
    end
  rescue Freno::Throttler::Error
  # Ignore freno errors and rely on retries from our own maintenance scheduler
  rescue GitHub::DGit::ReplicaCreateAlreadyPresentError
    # Ignore this case. This race does still occur in practice, but it's not
    # very interesting.
  end

  def perform!(gist_id, host, via: nil)
    Failbot.push(via: via) unless via.nil?

    gist = Gist.find_by(id: gist_id)
    raise GitHub::DGit::ReplicaCreateError, "There is no gist #{gist_id}" unless gist

    all_replicas = GitHub::DGit::Routing.all_gist_replicas(gist_id)
    Failbot.push delegate_replicas: all_replicas.inspect

    raise GitHub::DGit::ReplicaCreateError, "#{host} is not a DGit host" unless GitHub::DGit::get_hosts.include?(host)

    GitHub.stats.increment "dgit.#{host}.actions.create-gist" if GitHub.enterprise?
    GitHub.dogstats.increment "dgit", tags: ["action:create_gist", "host:#{host}"]

    # Insert the new replica in a CREATING state.
    begin
      with_write do
        gist_db = GitHub::DGit::DB.for_gist_id(gist_id)
        sql = gist_db.SQL.new \
                            gist_id: gist_id,
        host: host,
        checksum: "creating",
        state: GitHub::DGit::CREATING,
        read_weight: 0
        sql.add <<-SQL
              INSERT INTO gist_replicas (gist_id, host, checksum, state, read_weight, created_at, updated_at)
              VALUES (:gist_id, :host, :checksum, :state, :read_weight, NOW(), NOW())
            SQL
        gist_db.throttle { sql.run }
      end
    rescue ActiveRecord::RecordNotUnique
      raise GitHub::DGit::ReplicaCreateAlreadyPresentError, "There is already a replica of gist #{gist_id} on #{host}"
    end

    # Repair it into existence.  Abracadabra.
    GitHub.logger.info("start", "code.namespace" => "SpokesRepairGistReplicaJob", "code.function" => "perform!")
    SpokesRepairGistReplicaJob.new.perform!(gist_id, host, true, via: via)

  rescue GitHub::DGit::ReplicaRepairError => e
    GitHub::DGit::Maintenance::set_gist_state(gist_id, host, GitHub::DGit::FAILED)
    raise e
  end
end
