# typed: true
# frozen_string_literal: true

class HydroScheduleMaintenanceOnPushJob < Repositories::PushHydroMessageJob

  queue_as :hydro_schedule_maintenance_on_push

  def perform
    # Schedule network maintenance on large pushes (exceeding
    # Pushes::CommitsHelper::LARGE_PUSH_THRESHOLD)
    #
    # Pushes containing a large number of commits can make the repository
    # inaccessible without triggering a maintenance job via other heuristics.
    # This ensures they are processed, thus avoiding service failures.
    #
    # Note that maintenance jobs are scheduled only when a repository is
    # not already undergoing maintenance, and is also not scheduled to undergo
    # maintenance. This prevents our largest repositories from repeatedly
    # enqueueing expensive maintenance tasks.
    if repository.network&.maintenance_pending?
      GitHub.dogstats.increment("git.post_receive.maintenance", tags: ["pending:#{repository.network&.maintenance_status}"])
    else
      if large_push?
        schedule_maintenance
      else
        schedule_maintenance if ref_updates.any?(&:large_push?)
      end
    end
  end

  def schedule_maintenance
    ActiveRecord::Base.connected_to(role: :writing) do
      repository.network&.schedule_maintenance
    end
    GitHub.dogstats.increment("git.post_receive.maintenance", tags: ["scheduled:true"])
  end
end
