# typed: true
# frozen_string_literal: true

class HydroTimelinedLiveUpdateJob < HydroMessageJob
  extend T::Sig

  queue_as :hydro_timelined_live_update
  retry_on_dirty_exit

  sig { void }
  def perform
    return unless GitHub.flipper[:issues_create_timeline_entry_hydro_job].enabled?
    return unless topic == "github.timeline.v0.CreateTimelineEntry"
    return unless message
    return unless type = message.dig(:type)
    return unless type == "ProjectItemStatusChangedEvent" || type == "RemovedFromProjectEvent" || type == "AddedToProjectEvent"
    return unless issue_id = message.dig(:parent)&.dig(:id)
    return unless issue = Issue.find_by(id: issue_id)

    global_relay_id = issue.global_relay_id

    Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_timeline_updated: true, issue_metadata_updated: true })
  end
end
