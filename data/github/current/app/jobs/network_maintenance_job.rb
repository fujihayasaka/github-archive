# typed: false
# frozen_string_literal: true

class NetworkMaintenanceJob < ApplicationJob
  default_to_write_connection! # rubocop:todo GitHub/JobsDoNotDefaultToWriteConnection

  queue_as :network_maintenance

  Error = Class.new(StandardError)

  # Network maintenance can take quite a while on large repositories.
  # Make sure the job lock and GitRPC give it at least this much time
  # to run.
  BLOOM_FILTER_TIMEOUT = 10 * 60
  JOB_TIMEOUT = 240 * 60 + BLOOM_FILTER_TIMEOUT

  # Add a minute to the hashlock, so if the GitRPC operation runs hard up
  # against the timeout, another job doesn't start and immediately race
  # with the one that's ending.
  locked_by timeout: JOB_TIMEOUT + 60, key: -> (job) {
    job.arguments[0]
  }

  resolve_tenant_context do |network_id|
    ::RepositoryNetworks::Public.resolve_tenant(id: network_id)
  end

  def perform(network_id, previous_status: nil)
    Failbot.push spec: "network/#{network_id}"

    return unless network = ActiveRecord::Base.connected_to(role: :reading) { RepositoryNetwork.find_by_id(network_id) }

    GitHub.logger.with_named_tags("gh.spokes.spec" => network.dgit_spec, "code.function" => "perform") do
      GitHub.logger.info("starting git maintenance",
          "gh.spokes.maintenance.status" => network.maintenance_status,
          "gh.spokes.maintenance.elapsed" => Time.now - (network.last_maintenance_at || network.created_at),
          "gh.spokes.maintenance.pushes" => network.pushed_count_since_maintenance || 0)

      GitHub.dogstats.distribution_time("git_maintenance.dist.perform", tags: ["type:network"]) do
        perform!(network, previous_status)
      ensure
        status = network.maintenance_status
        tags = ["type:network", "result:#{status}"]
        if previous_status
          tags << "previous_result:#{previous_status}"
        end
        GitHub.dogstats.increment("git_maintenance", tags: tags)
      end
    ensure
      GitHub.logger.info("exiting git maintenance", "gh.spokes.maintenance.status" => network.maintenance_status)
    end

    nil
  end

  # Run network maintenance for the given network.
  def perform!(network, previous_status)
    # If a network has no root it's likely some sort of failed detach has
    # removed the actual data from this network. There is really nothing for
    # us to do here but mark it broken so we don't keep trying to perform
    # maintenance continuously.
    unless network.root
      network.mark_as_broken
      Failbot.report(Error.new("RepositoryNetwork has no valid root"), app: "github")
      return
    end

    # There is no maintenance to be done for orphaned networks so we should
    # just mark it as broken and move on.
    if network.orphaned?
      network.mark_as_broken
      Failbot.report(Error.new("RepositoryNetwork has become orphaned"), app: "github")
      return
    end

    # if a backup-utils backup is in progress, delay the maintenance operation
    # by requeuing after a short sleep period.
    if GitHub::Enterprise.backup_in_progress?
      clear_lock
      GitHub.logger.info("git maintenance delayed due to backup in progress")
      sleep 60
      network.schedule_maintenance
      return
    end

    GitHub.dogstats.time("network_maintenance") do
      begin
        network.perform_maintenance(previous_status)
      rescue GitRPC::Protocol::DGit::ResponseError => e
        GitHub.logger.error({ :exception => e, "gh.dgit.gitrpc.answers" => format_results(e.answers), "gh.dgit.gitrpc.errors" => format_results(e.errors) })
      end
    end
  end

  def format_results(results)
    results.map { |route, obj| "#{format_result(route, obj)}" }.join("/")
  end

  def format_result(route, obj)
    "#{::GitRPC::Protocol::DGit.format_route(route)} => {out => #{obj["out"].dump}, err => #{obj["err"].dump}}"
  end
end
