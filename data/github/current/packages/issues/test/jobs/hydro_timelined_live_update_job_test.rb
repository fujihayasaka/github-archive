# typed: true
# frozen_string_literal: true

require "test_helper"

class TimelinedLiveUpdateJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  fixtures do
    @issue = create(:issue)
  end

  test "it triggers an issue timeline subscriptions when issues_create_timeline_entry_hydro_job is enabled for known event types", feature_enabled: :issues_create_timeline_entry_hydro_job, skip_enterprise: true do
    %w(ProjectItemStatusChangedEvent RemovedFromProjectEvent AddedToProjectEvent).each do |type|
      message = {
        type: type,
        parent: {
          id: @issue.id
        }
      }

      Platform::Schema.subscriptions.expects(:trigger).once.with(
        :issue_updated,
        { id: @issue.global_relay_id },
        object: { issue_timeline_updated: true, issue_metadata_updated: true }
      )

      perform_hydro_message_job(message, schema: "github.timeline.v0.CreateTimelineEntry", queue: "hydro_timelined_live_update")
    end
  end

  test "it does not trigger an issue timeline subscriptions when issues_create_timeline_entry_hydro_job is disabled", feature_disabled: :issues_create_timeline_entry_hydro_job, skip_enterprise: true do
    message = {
      type: "ProjectItemStatusChangedEvent",
      parent: {
        id: @issue.id
      }
    }

    Platform::Schema.subscriptions.expects(:trigger).never

    perform_hydro_message_job(message, schema: "github.timeline.v0.CreateTimelineEntry", queue: "hydro_timelined_live_update")
  end

  test "it does not trigger an issue timeline subscriptions if the issue is not found", feature_enabled: :issues_create_timeline_entry_hydro_job, skip_enterprise: true do
    GitHub.flipper[:issues_create_timeline_entry_hydro_job].disable

    message = {
      type: "ProjectItemStatusChangedEvent",
      parent: {
        id: 123456
      }
    }

    Platform::Schema.subscriptions.expects(:trigger).never

    perform_hydro_message_job(message, schema: "github.timeline.v0.CreateTimelineEntry", queue: "hydro_timelined_live_update")
  end

  test "it does not trigger an issue timeline subscriptions when the type is custom", feature_enabled: :issues_create_timeline_entry_hydro_job, skip_enterprise: true do
    message = {
      type: "CustomType",
      parent: {
        id: @issue.id
      }
    }

    Platform::Schema.subscriptions.expects(:trigger).never

    perform_hydro_message_job(message, schema: "github.timeline.v0.CreateTimelineEntry", queue: "hydro_timelined_live_update")
  end
end
