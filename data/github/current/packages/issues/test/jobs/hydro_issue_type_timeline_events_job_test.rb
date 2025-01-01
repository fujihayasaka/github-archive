# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroIssueTypeTimelineEventsJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  def setup
    @org = create(:organization)
    @user = create :user
    @org.add_member(@user, action: :admin)
    @repo = create :repository, owner: @org
    @issue = create :issue, repository: @repo

    # Disable the killswitch for this test suite
    disable_feature_flag(:issue_type_timeline_events_job_killswitch)
  end

  test "issue type timeline events are created correctly for add events" do
    issue_type = @org.issue_types.first
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: issue_type.id,
        name: issue_type.name,
        color: issue_type.color,
      },
      prev_issue_type: nil,
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 1, @issue.events.count

    event = @issue.events.first
    event_detail = event.issue_event_detail

    assert_equal "issue_type_added", event.event
    assert_equal @user, event.actor
    assert_equal @issue.id, event.issue_id

    assert_equal issue_type.id, event_detail.issue_type_id
    assert_equal issue_type.name, event_detail.issue_type_name
    assert_equal issue_type.color, event_detail.issue_type_color

    assert_nil event_detail.prev_issue_type_id
    assert_nil event_detail.prev_issue_type_name
    assert_nil event_detail.prev_issue_type_color
  end

  test "issue type timeline events are not created when killswitch is enabled" do
    enable_feature_flag(:issue_type_timeline_events_job_killswitch)

    issue_type = @org.issue_types.first
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: issue_type.id,
        name: issue_type.name,
        color: issue_type.color,
      },
      prev_issue_type: nil,
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 0, @issue.events.count
  end

  test "issue type timeline events are created correctly for remove events" do
    issue_type = @org.issue_types.first
    message = {
      action: "issue.untyped",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: issue_type.id,
        name: issue_type.name,
        color: issue_type.color,
      },
      prev_issue_type: nil,
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 1, @issue.events.count

    event = @issue.events.first
    event_detail = event.issue_event_detail

    assert_equal "issue_type_removed", event.event
    assert_equal @user, event.actor
    assert_equal @issue.id, event.issue_id

    assert_nil event_detail.issue_type_id
    assert_nil event_detail.issue_type_name
    assert_nil event_detail.issue_type_color

    assert_equal issue_type.id, event_detail.prev_issue_type_id
    assert_equal issue_type.name, event_detail.prev_issue_type_name
    assert_equal issue_type.color, event_detail.prev_issue_type_color
  end

  test "issue type timeline events are created correctly for change events" do
    old_issue_type = @org.issue_types.first
    new_issue_type = @org.issue_types.second
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: new_issue_type.id,
        name: new_issue_type.name,
        color: new_issue_type.color,
      },
      prev_issue_type: {
        id: old_issue_type.id,
        name: old_issue_type.name,
        color: old_issue_type.color,
      },
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 1, @issue.events.count

    event = @issue.events.first
    event_detail = event.issue_event_detail

    assert_equal "issue_type_changed", event.event
    assert_equal @user, event.actor
    assert_equal @issue.id, event.issue_id

    assert_equal new_issue_type.id, event_detail.issue_type_id
    assert_equal new_issue_type.name, event_detail.issue_type_name
    assert_equal new_issue_type.color, event_detail.issue_type_color

    assert_equal old_issue_type.id, event_detail.prev_issue_type_id
    assert_equal old_issue_type.name, event_detail.prev_issue_type_name
    assert_equal old_issue_type.color, event_detail.prev_issue_type_color
  end

  test "issue type timeline events are not created for add events when issue type is private" do
    issue_type = create :issue_type, owner: @org, name: "private", color: "red", private: true
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: issue_type.id,
        name: issue_type.name,
        color: issue_type.color,
        private: issue_type.private,
      },
      prev_issue_type:  nil,
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 0, @issue.events.count
  end

  test "issue type timeline events are not created for remove events when issue type is private" do
    issue_type = create :issue_type, owner: @org, name: "private", color: "red", private: true
    message = {
      action: "issue.untyped",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type:  {
        id: issue_type.id,
        name: issue_type.name,
        color: issue_type.color,
        private: issue_type.private,
      },
      prev_issue_type: nil,
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 0, @issue.events.count
  end

  test "issue type timeline events are not created for change events when issue type and prev issue type are private" do
    prev_issue_type = create :issue_type, owner: @org, name: "prev private", color: "red", private: true
    issue_type = create :issue_type, owner: @org, name: "private", color: "red", private: true
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: issue_type.id,
        name: issue_type.name,
        color: issue_type.color,
        private: issue_type.private,
      },
      prev_issue_type: {
        id: prev_issue_type.id,
        name: prev_issue_type.name,
        color: prev_issue_type.color,
        private: prev_issue_type.private,
      },
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    assert_equal 0, @issue.events.count
  end

  test "issue type timeline events are created as add events if prev issue type is private, but issue type is public" do
    public_issue_type = create :issue_type, owner: @org, name: "public", color: "red", private: false
    private_issue_type = create :issue_type, owner: @org, name: "private", color: "red", private: true
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: public_issue_type.id,
        name: public_issue_type.name,
        color: public_issue_type.color,
        private: public_issue_type.private,
      },
      prev_issue_type: {
        id: private_issue_type.id,
        name: private_issue_type.name,
        color: private_issue_type.color,
        private: private_issue_type.private,
      },
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    event = @issue.events.first
    event_detail = event.issue_event_detail

    assert_equal "issue_type_added", event.event
    assert_equal @user, event.actor
    assert_equal @issue.id, event.issue_id

    assert_equal public_issue_type.id, event_detail.issue_type_id
    assert_equal public_issue_type.name, event_detail.issue_type_name
    assert_equal public_issue_type.color, event_detail.issue_type_color
    refute event_detail.issue_type_private

    assert_nil event_detail.prev_issue_type_id
    assert_nil event_detail.prev_issue_type_name
    assert_nil event_detail.prev_issue_type_color
    refute event_detail.prev_issue_type_private
  end

  test "issue type timeline events are created as remove events if prev issue type is public, but issue type is private" do
    public_issue_type = create :issue_type, owner: @org, name: "public", color: "red", private: false
    private_issue_type = create :issue_type, owner: @org, name: "private", color: "red", private: true
    message = {
      action: "issue.typed",
      actor: {
        id: @user.id,
      },
      issue: {
        id: @issue.id,
      },
      issue_type: {
        id: private_issue_type.id,
        name: private_issue_type.name,
        color: private_issue_type.color,
        private: private_issue_type.private,
      },
      prev_issue_type: {
        id: public_issue_type.id,
        name: public_issue_type.name,
        color: public_issue_type.color,
        private: public_issue_type.private,
      },
    }

    perform_hydro_message_job(message, schema: "github.v1.IssueUpdateIssueType", queue: "hydro_issue_type_timeline_events")

    event = @issue.events.first
    event_detail = event.issue_event_detail

    assert_equal "issue_type_removed", event.event
    assert_equal @user, event.actor
    assert_equal @issue.id, event.issue_id

    assert_equal public_issue_type.id, event_detail.prev_issue_type_id
    assert_equal public_issue_type.name, event_detail.prev_issue_type_name
    assert_equal public_issue_type.color, event_detail.prev_issue_type_color
    refute event_detail.prev_issue_type_private

    assert_nil event_detail.issue_type_id
    assert_nil event_detail.issue_type_name
    assert_nil event_detail.issue_type_color
    refute event_detail.issue_type_private
  end
end
