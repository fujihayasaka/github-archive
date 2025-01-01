# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventProjectsV2EventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    @admin = create(:verified_user)
    @org = create(:organization, admin: @admin)
    @actor = create(:user, login: "actor")
    @project = create(:memex_project, owner: @org, title: "My Memex Project")
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  private def create_event(action: :created, project: @project, actor: @actor)
    Hook::Event::ProjectsV2Event.new(
      action: action,
      project_id: project.id,
      actor_id: actor.id,
      org_id: project.organization_owner_id
    )
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ProjectsV2Event, :action, :project_id, :org_id, :actor_id
  end

  context "#project" do
    test "returns the project" do
      event = create_event
      assert_equal @project, event.project
    end

    test "returns nil if the project no longer exists" do
      event = create_event
      @project.destroy!

      assert_nil event.project
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

    test "returns false if the project is missing" do
      event = create_event
      @project.destroy!

      refute_predicate event, :deliverable?
    end
  end
end
