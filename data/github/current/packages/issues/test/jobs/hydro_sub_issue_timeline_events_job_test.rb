# typed: true
# frozen_string_literal: true

require "test_helper"

class HydroSubIssueTimelineEventsJobTest < GitHub::TestCase
  include HydroMessageJobTestHelpers

  DATE_FORMAT = "%Y-%m-%dT%H:%M:%S".freeze

  def setup
    @user = create :user
    @repo = create :repository, owner: @user
    @parent = create :issue, repository: @repo
    @child = create :issue, repository: @repo

    @parent.add_sub_issue!(@child, @user.id)
  end

  test "sub-issue timeline events are created correctly for sub-issue add events" do
    Timecop.freeze(Time.now.strftime(DATE_FORMAT)) do
      message = {
        source_issue: {
          id: @parent.id
        },
        target_issue: {
          id: @child.id
        },
        actor: {
          id: @user.id
        },
      }

      perform_hydro_message_job(message, schema: "github.v1.SubIssueAdd", queue: "hydro_sub_issue_timeline_events")

      # parent events
      assert_equal 1, @parent.events.count
      event = @parent.events.first

      assert_equal "sub_issue_added", event.event
      assert_equal @user, event.actor
      assert_equal @child, event.subject
      assert_equal @child.id, event.subject_id
      assert_equal "Issue", event.subject_type
      assert_equal Time.now + 1.second, event.created_at

      # sub-issue events
      assert_equal 1, @child.events.count
      event = @child.events.first

      assert_equal "parent_issue_added", event.event
      assert_equal @user, event.actor
      assert_equal @parent, event.subject
      assert_equal @parent.id, event.subject_id
      assert_equal "Issue", event.subject_type
      assert_equal Time.now + 1.second, event.created_at
    end
  end

  test "sub-issue timeline events are created correctly for sub-issue remove events" do
    Timecop.freeze(Time.now.strftime(DATE_FORMAT)) do


      message = {
        source_issue: {
          id: @parent.id
        },
        target_issue: {
          id: @child.id
        },
        actor: {
          id: @user.id
        },
      }

      perform_hydro_message_job(message, schema: "github.v1.SubIssueRemove", queue: "hydro_sub_issue_timeline_events")

      # parent events
      assert_equal 1, @parent.events.count
      event = @parent.events.first

      assert_equal "sub_issue_removed", event.event
      assert_equal @user, event.actor
      assert_equal @child, event.subject
      assert_equal @child.id, event.subject_id
      assert_equal "Issue", event.subject_type
      assert_equal Time.now, event.created_at

      # sub-issue events
      assert_equal 1, @child.events.count
      event = @child.events.first

      assert_equal "parent_issue_removed", event.event
      assert_equal @user, event.actor
      assert_equal @parent, event.subject
      assert_equal @parent.id, event.subject_id
      assert_equal "Issue", event.subject_type
      assert_equal Time.now, event.created_at
    end
  end

  test "sub-issue timeline events are not created for sub-issue add events when sub-issue is deleted" do
    Timecop.freeze(Time.now.strftime(DATE_FORMAT)) do
      message = {
        source_issue: {
          id: @parent.id
        },
        target_issue: {
          id: @child.id
        },
        actor: {
          id: @user.id
        },
      }

      @child.destroy

      perform_hydro_message_job(message, schema: "github.v1.SubIssueAdd", queue: "hydro_sub_issue_timeline_events")

      # parent events
      assert_equal 0, @parent.events.count

      # sub-issue events
      assert_equal 0, @child.events.count
    end
  end

  test "sub-issue timeline events are not created for sub-issue add events when parent is deleted" do
    Timecop.freeze(Time.now.strftime(DATE_FORMAT)) do
      message = {
        source_issue: {
          id: @parent.id
        },
        target_issue: {
          id: @child.id
        },
        actor: {
          id: @user.id
        },
      }

      @parent.destroy

      perform_hydro_message_job(message, schema: "github.v1.SubIssueAdd", queue: "hydro_sub_issue_timeline_events")

      # parent events
      assert_equal 0, @parent.events.count

      # sub-issue events
      assert_equal 0, @child.events.count
    end
  end

  test "sub-issue timeline events are not created for sub-issue remove events when sub-issue is deleted" do
    Timecop.freeze(Time.now.strftime(DATE_FORMAT)) do
      message = {
        source_issue: {
          id: @parent.id
        },
        target_issue: {
          id: @child.id
        },
        actor: {
          id: @user.id
        },
      }

      @child.destroy

      perform_hydro_message_job(message, schema: "github.v1.SubIssueRemove", queue: "hydro_sub_issue_timeline_events")

      # parent events
      assert_equal 0, @parent.events.count

      # sub-issue events
      assert_equal 0, @child.events.count
    end
  end

  test "sub-issue timeline events are not created for sub-issue remove events when parent is deleted" do
    Timecop.freeze(Time.now.strftime(DATE_FORMAT)) do
      message = {
        source_issue: {
          id: @parent.id
        },
        target_issue: {
          id: @child.id
        },
        actor: {
          id: @user.id
        },
      }

      @parent.destroy

      perform_hydro_message_job(message, schema: "github.v1.SubIssueRemove", queue: "hydro_sub_issue_timeline_events")

      # parent events
      assert_equal 0, @parent.events.count

      # sub-issue events
      assert_equal 0, @child.events.count
    end
  end
end
