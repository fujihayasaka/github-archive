# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

class ScienceEventCleanupJob < ApplicationJob
  schedule interval: 30.minutes, condition: -> { !GitHub.enterprise? }

  queue_as :science_event_cleanup
  retry_on_dirty_exit

  def perform
    GitHub.dogstats.distribution_time("science_events.cleanup_job") do
      ScienceEvent.trim_all
    end
  end
end
