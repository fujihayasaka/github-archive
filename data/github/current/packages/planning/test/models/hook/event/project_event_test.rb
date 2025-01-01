# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventProjectEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    #org project
    @org_project = create(:org_project)
    @org         = @org_project.owner

    #org-owned repo project
    @org_repo         = create(:org_owned_repository, owner: @org)
    @org_repo_project = create(:project, owner: @org_repo)

    #user-owned repo project
    @user_repo_project = create(:project)

    @actor = create(:user, login: "actor")


    @changes = {
      old_body: "Body",
      body: "Changed Body",
      old_name: "Name",
      name: "Changed Name",
      old_track_progress: false,
      track_progress: true,
    }
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ProjectEvent, :action, :project_id, :actor_id
  end

  context "#project" do
    test "returns an active project" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: @actor.id)
      assert_equal @org_project, event.project
    end

    test "returns nil for an archived project" do
      archived_project = Archived::Project.archive(@org_project)
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: archived_project.id, actor_id: @actor.id)
      assert_nil event.project
    end
  end

  context "#target_repository" do
    test "returns nil when org level project" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: @actor.id)
      assert_nil event.target_repository
    end

    test "returns repository when repo level project" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_repo_project.id, actor_id: @actor.id)
      assert_equal @org_repo, event.target_repository
    end
  end

  context "#target_organization" do
    test "returns the project's owning org when project is org level" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: @actor.id)
      assert_equal @org, event.target_organization
    end

    test "returns repo's owning org when repo level project and repo is org owned" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_repo_project.id, actor_id: @actor.id)
      assert_equal @org_repo.owner, event.target_organization
    end

    test "returns nil when repo level project and repo is user owned" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @user_repo_project.id, actor_id: @actor.id)
      assert_nil event.target_organization
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: @actor.id)
      assert_equal @actor, event.actor
    end

    test "doesn't error when the actor_id is not found" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: 0)
      assert_nil event.actor
    end
  end

  context "#deliverable?" do
    test "returns true for an active project" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: @actor.id)
      assert_predicate event, :deliverable?
    end

    test "returns false for an archived project" do
      archived_project = Archived::Project.archive(@org_project)
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: archived_project.id, actor_id: @actor.id)
      refute_predicate event, :deliverable?
    end
  end

  context "#deliver" do
    test "handles deleted project" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_repo_project.id, actor_id: @actor.id)
      @org_repo_project.destroy

      assert_nil event.target_repository
      assert_nil event.target_organization
      assert_nil event.project
      event.deliver
    end
  end

  context "#model_importing?" do
    test "returns true when the repo locked for migration" do
      @org_repo.lock_for_migration
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_repo_project.id, actor_id: @actor.id)
      assert event.model_importing?
      assert_predicate event, :model_importing?
    end

    test "returns false when the repo is not locked for migration" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_repo_project.id, actor_id: @actor.id)
      refute event.model_importing?
      refute_predicate event, :model_importing?
    end
  end

  context "#changes" do
    test "includes the original version of the body and name when changed values passed to the event" do
      event = Hook::Event::ProjectEvent.new(action: :edited, project_id: @org_project.id, actor_id: @actor.id, changes: @changes)
      assert_equal event.changes[:body][:from], "Body"
      assert_equal event.changes[:name][:from], "Name"
      assert_nil event.changes[:track_progress]
    end

    test "does not include the original version if they're not passed to the event" do
      event = Hook::Event::ProjectEvent.new(action: :edited, project_id: @org_project.id, actor_id: @actor.id, changes: nil)
      assert_nil event.changes
    end

    test "no changes if only the project's track progress setting was changed" do
      track_progress_only_change = {
        old_track_progress: false,
        track_progress: true,
      }
      event = Hook::Event::ProjectEvent.new(action: :edited, project_id: @org_project.id, actor_id: @actor.id, changes: track_progress_only_change)
      assert_nil event.changes
    end
  end
end
