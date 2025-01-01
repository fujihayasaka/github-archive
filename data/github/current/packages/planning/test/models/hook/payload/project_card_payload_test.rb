# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadProjectCardPayloadTest < GitHub::TestCase
  include PlatformTestHelpers::InterfaceHelpers
  include ProjectCardHelpers

  fixtures do
    # org project
    org_project     = create(:org_project)
    org_project_col = create(:project_column, project: org_project)
    @org_card_note  = create(:project_card, column: org_project_col, note: "Orgs are the best", created_at: "2016-01-03T16:00:49Z", updated_at: "2017-04-16T16:00:49Z")
    @org            = org_project.owner

    # org-owned repo project
    @org_repo            = create(:org_owned_repository, owner: @org)
    org_repo_project     = create(:project, owner: @org_repo)
    org_repo_project_col = create(:project_column, project: org_repo_project)
    @org_repo_card_note  = create(:project_card, column: org_repo_project_col, note: "Yes, they are")

    # user-owned repo project
    user_repo_project     = create(:project)
    @user_repo            = user_repo_project.owner
    user_repo_project_col = create(:project_column, project: user_repo_project)
    @user_repo_card_note  = create(:project_card, column: user_repo_project_col, note: "Users aren't so bad either")

    # cards with issues
    @org_issue       = create(:issue, repository: @org_repo)
    @org_repo_issue  = create(:issue, repository: @org_repo)
    @user_repo_issue = create(:issue, repository: @user_repo)

    @org_card_issue       = create(:project_card, column: org_project_col, content: @org_issue)
    @org_repo_card_issue  = create(:project_card, column: org_repo_project_col, content: @org_repo_issue)
    @user_repo_card_issue = create(:project_card, column: user_repo_project_col, content: @user_repo_issue)

    @actor = create(:user, login: "actor")

    # actor will be creating content, so needs to be a member
    @org.add_member(@actor)
    @org_repo.add_member(@actor)
    @user_repo.add_member(@actor)

    @note_changes = {
      old_note: "Placeholder",
      note: "Meeting is set",
    }

    @convert_changes = {
      old_note: "Make an issue when done",
      note: nil,
    }
  end

  setup do
    GitHub.context.push(actor_id: @actor.id)
  end

  context "v3 org project" do
    test "when project card with note is created" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_card_note.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_card_note.id, v3[:project_card][:id]
      assert_equal @org_card_note.note, v3[:project_card][:note]
      assert_equal @org_card_note.column_id, v3[:project_card][:column_id]
      assert_equal "2016-01-03T16:00:49Z", v3[:project_card][:created_at]
      assert_equal "2017-04-16T16:00:49Z", v3[:project_card][:updated_at]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
    end

    test "when project card with issue content is created" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_card_issue.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_card_issue.id, v3[:project_card][:id]
      assert_equal @org_card_issue.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
    end

    test "when project card's note is edited" do
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_card_note.id, actor_id: @actor.id, changes: @note_changes)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @org_card_note.id, v3[:project_card][:id]
      assert_equal @org_card_note.note, v3[:project_card][:note]
      assert_equal @org_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
      refute_nil   v3[:changes]
      assert_equal "Placeholder", v3[:changes][:note][:from]
    end

    test "when project card's note is converted to an issue" do
      convert_note_to_issue(card: @org_card_note, converter: @actor, repository: @org_repo, title: "New Issue", body: "TBD")

      event = Hook::Event::ProjectCardEvent.new(action: :converted, project_card_id: @org_card_note.id, actor_id: @actor.id, changes: @convert_changes)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :converted, v3[:action]
      assert_equal @org_card_note.id, v3[:project_card][:id]
      assert_equal @org_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
      refute_nil   v3[:changes]
      assert_equal "Make an issue when done", v3[:changes][:note][:from]
    end

    test "when project card is moved" do
      event = Hook::Event::ProjectCardEvent.new(action: :moved, project_card_id: @org_card_note.id, actor_id: @actor.id, after_id: 2)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :moved, v3[:action]
      assert_equal @org_card_note.id, v3[:project_card][:id]
      assert_equal @org_card_note.note, v3[:project_card][:note]
      assert_equal @org_card_note.column_id, v3[:project_card][:column_id]
      assert_equal 2, v3[:project_card][:after_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
      assert_nil   v3[:changes]
    end

    test "when project card is deleted" do
      event = Hook::Event::ProjectCardEvent.new(action: :deleted, project_card_id: @org_card_note.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_card_note.id, v3[:project_card][:id]
      assert_equal @org_card_note.note, v3[:project_card][:note]
      assert_equal @org_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
    end
  end

  context "v3 org-owned repo project" do
    test "when project card with note is created" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_repo_card_note.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_repo_card_note.id, v3[:project_card][:id]
      assert_equal @org_repo_card_note.note, v3[:project_card][:note]
      assert_equal @org_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project card with issue content is created" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @org_repo_card_issue.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_repo_card_issue.id, v3[:project_card][:id]
      assert_equal @org_repo_card_issue.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project card's note is edited" do
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @org_repo_card_note.id, actor_id: @actor.id, changes: @note_changes)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @org_repo_card_note.id, v3[:project_card][:id]
      assert_equal @org_repo_card_note.note, v3[:project_card][:note]
      assert_equal @org_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      refute_nil   v3[:changes]
      assert_equal "Placeholder", v3[:changes][:note][:from]
    end

    test "when project card's note is converted to an issue" do
      convert_note_to_issue(card: @org_repo_card_note, converter: @actor, repository: @org_repo, title: "New Issue", body: "TBD")

      event = Hook::Event::ProjectCardEvent.new(action: :converted, project_card_id: @org_repo_card_note.id, actor_id: @actor.id, changes: @convert_changes)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :converted, v3[:action]
      assert_equal @org_repo_card_note.id, v3[:project_card][:id]
      assert_equal @org_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      refute_nil   v3[:changes]
      assert_equal "Make an issue when done", v3[:changes][:note][:from]
    end

    test "when project card is moved" do
      event = Hook::Event::ProjectCardEvent.new(action: :moved, project_card_id: @org_repo_card_issue.id, actor_id: @actor.id, after_id: 4)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :moved, v3[:action]
      assert_equal @org_repo_card_issue.id, v3[:project_card][:id]
      assert_equal @org_repo_card_issue.column_id, v3[:project_card][:column_id]
      assert_equal 4, v3[:project_card][:after_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project card is deleted" do
      event = Hook::Event::ProjectCardEvent.new(action: :deleted, project_card_id: @org_repo_card_issue.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_repo_card_issue.id, v3[:project_card][:id]
      assert_equal @org_repo_card_issue.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project card is deleted and the issue belongs to a deleted repository" do
      @org_repo.destroy
      event = Hook::Event::ProjectCardEvent.new(action: :deleted, project_card_id: @org_card_issue.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_card_issue.id, v3[:project_card][:id]
      assert_equal @org_card_issue.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      assert_nil   v3[:project_card][:content_url]
      assert_nil   v3[:repository]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end
  end

  context "v3 user-owned repo project" do
    test "when project card with note is created" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @user_repo_card_note.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @user_repo_card_note.id, v3[:project_card][:id]
      assert_equal @user_repo_card_note.note, v3[:project_card][:note]
      assert_equal @user_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
    end

    test "when project card with issue content is created" do
      event = Hook::Event::ProjectCardEvent.new(action: :created, project_card_id: @user_repo_card_issue.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @user_repo_card_issue.id, v3[:project_card][:id]
      assert_equal @user_repo_card_issue.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:note]
      refute_nil   v3[:project_card][:content_url]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
    end

    test "when project card's note is edited" do
      event = Hook::Event::ProjectCardEvent.new(action: :edited, project_card_id: @user_repo_card_note.id, actor_id: @actor.id, changes: @note_changes)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @user_repo_card_note.id, v3[:project_card][:id]
      assert_equal @user_repo_card_note.note, v3[:project_card][:note]
      assert_equal @user_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
      refute_nil   v3[:changes]
      assert_equal "Placeholder", v3[:changes][:note][:from]
    end

    test "when project card's note is converted to an issue" do
      convert_note_to_issue(card: @user_repo_card_note, converter: @actor, repository: @user_repo, title: "New Issue", body: "TBD")

      event = Hook::Event::ProjectCardEvent.new(action: :converted, project_card_id: @user_repo_card_note.id, actor_id: @actor.id, changes: @convert_changes)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :converted, v3[:action]
      assert_equal @user_repo_card_note.id, v3[:project_card][:id]
      assert_equal @user_repo_card_note.column_id, v3[:project_card][:column_id]
      refute_nil   v3[:project_card][:content_url]
      assert_nil   v3[:project_card][:note]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
      refute_nil   v3[:changes]
      assert_equal "Make an issue when done", v3[:changes][:note][:from]
    end

    test "when project card is moved" do
      event = Hook::Event::ProjectCardEvent.new(action: :moved, project_card_id: @user_repo_card_note.id, actor_id: @actor.id, after_id: 9)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :moved, v3[:action]
      assert_equal @user_repo_card_note.id, v3[:project_card][:id]
      assert_equal @user_repo_card_note.note, v3[:project_card][:note]
      assert_equal @user_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_equal 9, v3[:project_card][:after_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
    end

    test "when project card is deleted" do
      event = Hook::Event::ProjectCardEvent.new(action: :deleted, project_card_id: @user_repo_card_note.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectCardPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @user_repo_card_note.id, v3[:project_card][:id]
      assert_equal @user_repo_card_note.note, v3[:project_card][:note]
      assert_equal @user_repo_card_note.column_id, v3[:project_card][:column_id]
      assert_nil   v3[:project_card][:content_url]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
    end
  end
end
