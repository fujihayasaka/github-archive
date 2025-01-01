# typed: false
# frozen_string_literal: true

require "github/timeout_and_measure"
require "github/pages/management/delegate"
require "github/pages/management/repair"

class DpagesRepairSiteJob < ApplicationJob
  queue_as :dpages_maintenance
  exempt_from_tenant_context_requirement

  class RepairFailed < RuntimeError
  end

  locked_by timeout: 1.hour, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  include GitHub::TimeoutAndMeasure

  # Perform the evacuation, limited to max_execution_time, with logs and stats along the way.
  def perform(page_id, page_deployment_id, voting, opts = { deligate: nil })
    @delegate = opts[:delegate] || GitHub::Pages::Management::Delegate.new(logger: GitHub::Logger)
    validate_args!(page_id, page_deployment_id, voting)
    return false if should_skip_repair?(page_id, page_deployment_id)

    timeout_and_measure(max_execution_time.to_i, "pages.dpages_maintenance.work") do
      command = GitHub::Pages::Management::Repair.new(delegate: @delegate)

      Failbot.push(
        :app => "pages",
        "gh.pages.id" => page_id,
        "gh.pages.deployment.id" => page_deployment_id)
      @delegate.log "Repairing page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} voting=#{voting}"

      result = with_write do
        begin
          if !GitHub.enterprise? && GitHub.flipper[:pages_azure_dfs_host].enabled?
            command.repair_single_site_azure(page_id: page_id, page_deployment_id: page_deployment_id)
          else
            command.repair_single_site(page_id: page_id, page_deployment_id: page_deployment_id, voting: voting)
          end
        rescue GitHub::Pages::Management::ExecutionError => e
          Failbot.push(@delegate.logged)
          raise e
        end
      end

      if result.nil?
        @delegate.log "Nothing to repair for page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} voting=#{voting}"
        break false
      end

      unless result
        @delegate.log "Failed to repair page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} voting=#{voting}"
        Failbot.push(@delegate.logged)
        raise RepairFailed, "Repair failed"
      end

      true
    end
  end

  def validate_args!(page_id, page_deployment_id, voting)
    # args must contain [page_id, page_deployment_id, voting]
    unless page_id.is_a?(Integer)
      raise ArgumentError, "page_id must be an integer, but was #{page_id.class}: #{page_id.inspect}"
    end

    unless page_deployment_id.nil? || page_deployment_id.is_a?(Integer)
      raise ArgumentError, "page_deployment_id must be nil or an integer, but was #{page_deployment_id.class}: #{page_deployment_id.inspect}"
    end

    unless voting == true || voting == false
      raise ArgumentError, "voting must be true or false, but was #{voting.class}: #{voting.inspect}"
    end

    true
  end

  def should_skip_repair?(page_id, page_deployment_id)
    return false if page_deployment_id.nil?
    page = Page.find_by_id(page_id)
    deployment = Page::Deployment.find_by_id(page_deployment_id)

    # if page nil, deployment nil, page source branch !- deployment.ref_name, return true, and skip repiar.
    page.nil? || deployment.nil? || page.source_branch != deployment.ref_name
  end

  # Limit the execution time of this job so we don't have dangling repairs.
  # If it times out, then fine: the scheduler will enqueue it again.
  #
  # Enterprise customers have reported a need for a higher timeout due to
  # slow throughput on their networks.  We allow for higher timeouts for their
  # environment.
  def max_execution_time
    if GitHub.enterprise?
      60.minutes
    else
      10.minutes
    end
  end
end
