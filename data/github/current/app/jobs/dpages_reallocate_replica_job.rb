# typed: true
# frozen_string_literal: true

require "github/timeout_and_measure"
require "github/pages/management/delegate"

class DpagesReallocateReplicaJob < ApplicationJob
  queue_as :dpages_replicas_reallocations

  class ReallocateReplicaFailed < RuntimeError
  end

  include GitHub::TimeoutAndMeasure

  def perform(args, delegate: nil)
    @delegate = delegate || GitHub::Pages::Management::Delegate.new
    @args = args

    validate_args!

    timeout_and_measure(max_execution_time.to_i, "pages.reallocate_replica.timing") do
      Failbot.push(
        :app => "pages",
        "gh.pages.id" => @page_id,
        "gh.pages.deployment.id" => @pages_deployment_id,
        "gh.pages.target.host" => @target_host,
        "gh.pages.source.host" => @source_host)

      # Add replicas first before removing replicas to ensure we still meet replica strategy during the process
      added = begin
        with_write do
          GitHub::Pages::Management::AddReplica.new(
            page_id: @page_id,
            page_deployment_id: @pages_deployment_id,
            host: @target_host,
            delegate: @delegate,
            voting: @voting
          ).perform
        end
      rescue GitHub::Pages::Management::AddReplica::NoVotingReplicasError => e
        track_result(succeeded: false)

        Failbot.push(@delegate.logged)
        raise e
      end

      unless added
        track_result(succeeded: false)

        Failbot.push(@delegate.logged)
        raise ReallocateReplicaFailed, "Add replica failed"
      end

      removed = with_write do
        GitHub::Pages::Management::RemoveReplica.new(
          page_id: @page_id,
          page_deployment_id: @pages_deployment_id,
          host: @source_host,
          delegate: @delegate
        ).perform
      end

      unless removed
        track_result(succeeded: false)

        with_write do
          GitHub::Pages::Management::RemoveReplica.new(
            page_id: @page_id,
            page_deployment_id: @pages_deployment_id,
            host: @target_host,
            delegate: @delegate
          ).perform
        end

        Failbot.push(@delegate.logged)
        raise ReallocateReplicaFailed, "Remove replica failed"
      end

      track_result(succeeded: true)
      true
    end
  end

  def validate_args!
    if !@args.is_a?(Array) || @args.size != 5
      raise ArgumentError, "Invalid arguments: #{@args.inspect}"
    end

    @page_id, @pages_deployment_id, @target_host, @source_host, @voting = *@args

    unless @page_id.is_a?(Integer)
      raise ArgumentError, "page_id must be an integer, but was #{@page_id.class}: #{@page_id.inspect}"
    end

    unless @pages_deployment_id.nil? || @pages_deployment_id.is_a?(Integer)
      raise ArgumentError, "pages_deployment_id must be nil or an integer, but was #{@pages_deployment_id.class}: #{@pages_deployment_id.inspect}"
    end

    unless @target_host.is_a?(String) && @target_host.size > 0
      raise ArgumentError, "target_host must be a string, but was #{@target_host.class}: #{@target_host.inspect}"
    end

    unless @source_host.is_a?(String) && @source_host.size > 0
      raise ArgumentError, "source_host must be a string, but was #{@source_host.class}: #{@source_host.inspect}"
    end

    unless @voting.is_a?(TrueClass) || @voting.is_a?(FalseClass)
      raise ArgumentError, "voting must be a boolean, but was #{@voting.class}: #{@voting.inspect}"
    end

    true
  end

  # Limit the execution time of this job so we don't have dangling reallocations.
  # If it times out, then fine. Reallocation of the replica can be retried if needed.
  def max_execution_time
    10.minutes
  end

  def track_result(succeeded:)
    result = succeeded ? "succeed" : "fail"

    @delegate.log("Reallocate replica with page id #{@page_id} and deployment id #{@pages_deployment_id} from #{@source_host} to #{@target_host} #{result}ed")
    GitHub.dogstats.increment("pages.reallocate_replica", tags: ["result:#{result}", "source_host:#{@source_host}", "target_host:#{@target_host}"])
  end

  retry_on_dirty_exit
  retry_on_recoverable_exceptions
end
