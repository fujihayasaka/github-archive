# typed: true
# frozen_string_literal: true

require "test_helper"

class HookEventProjectCardEventTest < GitHub::TestCase
  include HookEventTestHelper

  fixtures do
    #org project
    @org_project      = create(:org_project)
    @org_project_col  = create(:project_column, project: @org_project)
    @org_project_card = create(:project_card, column: @org_project_col, note: "Yup")
    @org              = @org_project.owner

    #org-owned repo project
    @org_repo              = create(:org_owned_repository, owner: @org)
    @org_repo_project      = create(:project, owner: @org_repo)
    @org_repo_project_col  = create(:project_column, project: @org_repo_project)
    @org_repo_project_card = create(:project_card, column: @org_repo_project_col, note: "Yes")

    #user-owned repo project
    @user_repo_project      = create(:project)
    @user_repo_project_col  = create(:project_column, project: @user_repo_project)
    @user_repo_project_card = create(:project_card, column: @user_repo_project_col, note: "Maybe")

    @actor = create(:user, login: "actor")
  end

  test "required attributes" do
    assert_event_required_attributes Hook::Event::ProjectCardEvent, :action, :project_card_id, :actor_id
  end

  context "#project_card" do
    test "returns an active project's card" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: @actor.id)
      assert_equal @org_project_card, event.project_card
    end

    test "returns nil for an archived project's card" do
      only = [DestroyDependentRecordsJob]
      archived_project = perform_enqueued_jobs(only: only) { Archived::Project.archive(@org_project) }
      archived_project_card = archived_project.cards.first
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: archived_project_card.id, actor_id: @actor.id)
      assert_nil event.project_card
    end
  end

  context "#project" do
    test "returns the card's project" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: @actor.id)
      assert_equal @org_project, event.project
    end
  end

  context "#target_repository" do
    test "returns nil when org level project" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: @actor.id)
      assert_nil event.target_repository
    end

    test "returns repository when repo level project" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_repo_project_card.id, actor_id: @actor.id)
      assert_equal @org_repo, event.target_repository
    end
  end

  context "#target_organization" do
    test "returns the project's owning org when project is org level" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: @actor.id)
      assert_equal @org, event.target_organization
    end

    test "returns repo's owning org when repo level project and repo is org owned" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_repo_project_card.id, actor_id: @actor.id)
      assert_equal @org_repo.owner, event.target_organization
    end

    test "returns nil when repo level project and repo is user owned" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @user_repo_project_card.id, actor_id: @actor.id)
      assert_nil event.target_organization
    end
  end

  context "#actor" do
    test "returns the specified user" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: @actor.id)
      assert_equal @actor, event.actor
    end

    test "doesn't error when the actor_id is not found" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: 0)
      assert_nil event.actor
    end
  end

  context "#deliverable?" do
    test "returns true when the card's project is active" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_project_card.id, actor_id: @actor.id)
      assert_predicate event, :deliverable?
    end

    test "returns false when the card's project is archived" do
      archived_project = Archived::Project.archive(@org_project)
      archived_project_card = archived_project.cards.first
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: archived_project_card.id, actor_id: @actor.id)
      refute_predicate event, :deliverable?
    end
  end

  context "#changes" do
    test "includes the original version of the note when it is passed to the event" do
      changes = {
        old_note: "Old Note",
        note: "New Note",
      }
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_project_card.id, actor_id: @actor.id, changes: changes)
      assert_equal event.changes[:note][:from], "Old Note"
    end

    test "includes the original version of the note if it is passed to the event and the old or new value is nil" do
      changes = {
        old_note: nil,
        note: "New Note",
      }
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_project_card.id, actor_id: @actor.id, changes: changes)
      assert_nil event.changes[:note][:from]

      changes = {
        old_note: "Old Note",
        note: nil,
      }
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_project_card.id, actor_id: @actor.id, changes: changes)
      assert_equal event.changes[:note][:from], "Old Note"
    end

    test "does not include the original version if they're not passed to the event" do
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_project_card.id, actor_id: @actor.id, changes: nil)
      assert_nil event.changes
    end

    test "includes the original column_id of the card if passed to the event" do
      changes = {
        old_column_id: 1,
        column_id: @org_project_card.column_id,
      }
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_project_card.id, actor_id: @actor.id, changes: changes)
      assert_equal event.changes[:column_id][:from], 1
    end
  end
end
