# typed: true
# frozen_string_literal: true

require "github/timeout_and_measure"
require "github/pages/management/delegate"
require "github/pages/management/evacuate"

class DpagesEvacuateSiteJob < ApplicationJob
  queue_as :dpages_evacuations

  locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: ActiveJob::LockingJob::DEFAULT_LOCK_PROC

  class EvacuationFailed < RuntimeError
  end

  include GitHub::TimeoutAndMeasure

  # Perform the evacuation, limited to max_execution_time, with logs and stats along the way.
  def perform(*args, delegate: nil)
    @delegate = delegate || GitHub::Pages::Management::Delegate.new
    @args = args

    validate_args!

    timeout_and_measure(max_execution_time.to_i, "pages.dpages_evacuations.work") do
      page_id, page_deployment_id, host = *@args

      command = GitHub::Pages::Management::Evacuate.new(delegate: @delegate, host: host)
      Failbot.push(app: "pages", page_id: page_id, page_deployment_id: page_deployment_id, host: host)

      unless GitHub::Pages::Management::Evacuate.evacuating_hosts.include?(host)
        @delegate.log "Skipping evacution of page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect}:" \
          " host=#{host} no longer evacuting"
        break false
      end

      @delegate.log "Evacuating page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} from host=#{host}"

      result = begin
        with_write do
          command.evacuate_single_site(page_id: page_id, page_deployment_id: page_deployment_id)
        end
      rescue GitHub::Pages::Management::ExecutionError => e
        Failbot.push(@delegate.logged)
        raise e
      end

      unless result
        @delegate.log "Failed to evacuate page_id=#{page_id} page_deployment_id=#{page_deployment_id.inspect} from host=#{host}"
        Failbot.push(@delegate.logged)
        raise EvacuationFailed, "Evacuation failed for host #{host}"
      end

      true
    end
  end

  def validate_args!
    # args must contain [page_id, page_deployment_id, host]
    if !@args.is_a?(Array) || @args.size != 3
      raise ArgumentError, "invalid arguments: #{@args.inspect}"
    end

    page_id, page_deployment_id, host = *@args
    unless page_id.is_a?(Integer)
      raise ArgumentError, "page_id must be an integer, but was #{page_id.class}: #{page_id.inspect}"
    end

    unless page_deployment_id.nil? || page_deployment_id.is_a?(Integer)
      raise ArgumentError, "page_deployment_id must be nil or an integer, but was #{page_deployment_id.class}: #{page_deployment_id.inspect}"
    end

    unless host.is_a?(String) && host.size > 0
      raise ArgumentError, "host must be a string, but was #{host.class}: #{host.inspect}"
    end

    true
  end

  # Limit the execution time of this job so we don't have dangling evacuations.
  # If it times out, then fine: the scheduler will enqueue it again.
  def max_execution_time
    10.minutes
  end
end
