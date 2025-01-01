# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventProjectsV2StatusUpdateEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @actor = create(:user, login: "actor")
    @project = create(:memex_project, owner: @org, title: "My Memex Project")
    @status_update = create(:memex_project_status, memex_project: @project)
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  private def create_event(action: :created, memex_project_status: @status_update, actor: @actor, changes: nil)
    Hook::Event::ProjectsV2StatusUpdateEvent.new(
      action: action,
      memex_project_status_id: memex_project_status.id,
      actor_id: actor.id,
      org_id: @org.id,
      changes: changes
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ProjectsV2StatusUpdateEvent, :action, :memex_project_status_id, :org_id, :actor_id
  end

  context "#project_status" do
    test "returns the project_status" do
      event = create_event
      assert_equal @status_update, event.project_status
    end

    test "returns nil if the project no longer exists" do
      event = create_event
      @status_update.destroy!

      assert_nil event.project_status
    end
  end

  context "#actor" do
    test "returns a User" do
      event = create_event
      assert_equal @actor, event.actor
    end

    test "returns nil actor no longer exists" do
      event = create_event
      @actor.destroy!

      assert_nil event.actor
    end
  end

  context "#target_organization" do
    test "returns an Organization" do
      event = create_event
      assert_equal @org, event.target_organization
    end

    test "returns nil when the org no longer exists" do
      event = create_event
      @org.destroy!

      assert_nil event.target_organization
    end
  end

  context "#deliverable?" do
    test "returns true if project and project owner are all present" do
      event = create_event
      assert_predicate event, :deliverable?
    end

    test "returns false if the project owner is missing" do
      event = create_event
      @org.destroy!

      refute_predicate event, :deliverable?
    end

    test "returns false if the status update is missing" do
      event = create_event
      @status_update.destroy!

      refute_predicate event, :deliverable?
      refute_nil @project
    end
  end

  context "#changes" do
    test "includes changes when a body is edited" do
      changes = {
        body: ["old body", "new body"],
      }
      event = create_event(action: :edited, changes: changes)
      expected_changes = {
        body: {
          from: "old body",
          to: "new body",
        }
      }

      assert_equal expected_changes, event.changes
    end

    test "includes changes when a start_date is edited" do
      changes = {
        start_date: %w(2023-01-01 2023-01-02),
      }
      event = create_event(action: :edited, changes: changes)
      expected_changes = {
        start_date: {
          from: "2023-01-01",
          to: "2023-01-02",
        }
      }

      assert_equal expected_changes, event.changes
    end

    test "includes changes when a target_date is edited" do
      changes = {
        target_date: %w(2023-02-01 2023-02-02),
      }
      event = create_event(action: :edited, changes: changes)
      expected_changes = {
        target_date: {
          from: "2023-02-01",
          to: "2023-02-02",
        }
      }

      assert_equal expected_changes, event.changes
    end

    test "includes changes when a status is edited" do
      on_track_option_id = MemexProjectStatus.status_enum_string_to_id("ON_TRACK")
      complete_option_id = MemexProjectStatus.status_enum_string_to_id("COMPLETE")
      changes = {
        status_id: [on_track_option_id, complete_option_id],
      }
      event = create_event(action: :edited, changes: changes)
      expected_changes = {
        status: {
          from: "ON_TRACK",
          to: "COMPLETE",
        }
      }

      assert_equal expected_changes, event.changes
    end
  end
end
