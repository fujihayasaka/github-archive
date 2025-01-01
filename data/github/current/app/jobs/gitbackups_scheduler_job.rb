# typed: true
# frozen_string_literal: true

require "scientist"

class GitbackupsSchedulerJob < ApplicationJob
  queue_as :gitbackups_scheduler

  include Scientist

  # Adjust as the number of networks and workers changes
  schedule interval: 5.minutes, condition: -> { GitHub.realtime_backups_enabled? }

  exempt_from_tenant_context_requirement

  MAINTENANCE_JOB_THRESHOLD = 500

  def queue_length
    GitbackupsMaintenanceJob.queue_depth
  end

  # Run every interval.
  def perform
    Failbot.push app: "gitbackups"

    return if queue_length > MAINTENANCE_JOB_THRESHOLD

    # We give each kind a budget of 250, which need-maintenance splits into
    # most-active and least-maintained.
    budget = 250

    schedule_networks(budget)

    schedule_wikis(budget)

    schedule_gists(budget)
  end

  # Schedule up to +max+ networks for maintenance
  def schedule_networks(max)
    schedule_maintenance("networks", max: max, to_spec: lambda { |n| "network/#{n["network_id"]}" })
  end

  # Schedule up to +max+ wikis for maintenance
  def schedule_wikis(max)
    schedule_maintenance("wikis", max: max, to_spec: lambda { |w| "#{w["network_id"]}/#{w["repository_id"]}.wiki" })
  end

  # Schedule up to +max+ gists for maintenance
  def schedule_gists(max)
    schedule_maintenance("gists", max: max, to_spec: lambda { |g| "gist/#{g["repo_name"]}" })
  end

  # Returns which networks need maintenance.
  #
  # max - maximum number of results to return
  # count - minimum number of pending incrementals in order to return
  def schedule_maintenance(repo_type, max: 20, to_spec: nil)
    needing_maintenance = science "gitbackups.vitess.need-maintenance" do |e|
      e.use do
        GitHub::Backups.need_maintenance(repo_type, max: max)
      end
      e.try do
        GitHub::Backups.need_maintenance(repo_type, max: max, use_vitess: true)
      end
    end

    # Only those with over +count+ pending incrementals have enough going
    # on for us to run maintenance
    to_schedule = needing_maintenance.map(&to_spec)

    GitHub::Backups.schedule_maintenance(to_schedule)

    to_schedule.length
  end
end
