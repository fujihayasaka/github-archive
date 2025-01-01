# typed: true
# frozen_string_literal: true

class HydroProjectItemDestroyedLiveUpdateJob < HydroMessageJob
  queue_as :hydro_project_item_destroyed_live_update
  retry_on_dirty_exit

  sig { void }
  def perform
    return unless GitHub.flipper[:issues_react_v2].enabled?
    return unless topic == "github.memex.v0.ProjectItemDestroy"
    return unless message
    return unless global_relay_id = message.dig(:memex_project_item, :issue, :global_relay_id)

    Platform::Schema.subscriptions.trigger(:issue_updated, { id: global_relay_id }, object: { issue_metadata_updated: true })
  end
end
