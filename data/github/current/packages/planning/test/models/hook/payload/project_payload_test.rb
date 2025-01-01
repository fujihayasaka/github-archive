# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadProjectPayloadTest < GitHub::TestCase
  fixtures do
    #org project
    @org_project = create(:org_project,
      created_at: "2016-01-03T16:00:49Z",
      updated_at: "2017-04-16T16:00:49Z",
    )
    @org         = @org_project.owner

    #org-owned repo project
    @org_repo         = create(:org_owned_repository, owner: @org)
    @org_repo_project = create(:project, owner: @org_repo)

    #user-owned repo project
    @user_repo_project = create(:project)
    @user_repo         = @user_repo_project.owner

    @actor       = create(:user, login: "actor")

    @changes = {
      old_body: "Body",
      body: "Changed Body",
      old_name: "Name",
      name: "Changed Name",
      old_track_progress: false,
      track_progress: true,
    }
  end

  context "v3 org project" do
    test "when project is created" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_project.id, v3[:project][:id]
      assert_equal @org_project.name, v3[:project][:name]
      assert_equal "2016-01-03T16:00:49Z", v3[:project][:created_at]
      assert_equal "2017-04-16T16:00:49Z", v3[:project][:updated_at]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
    end

    test "when project's name and body are updated" do
      event = Hook::Event::ProjectEvent.new(action: :edited, project_id: @org_project.id, actor_id: @actor.id, changes: @changes)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @org_project.id, v3[:project][:id]
      assert_equal @org_project.name, v3[:project][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_equal "Body", v3[:changes][:body][:from]
      assert_equal "Name", v3[:changes][:name][:from]
      assert_nil   v3[:changes][:track_progress]
      assert_nil   v3[:repository]
    end

    test "when project is closed" do
      event = Hook::Event::ProjectEvent.new(action: :closed, project_id: @org_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :closed, v3[:action]
      assert_equal @org_project.id, v3[:project][:id]
      assert_equal @org_project.name, v3[:project][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
      assert_nil   v3[:changes]
    end

    test "when project is reopened" do
      event = Hook::Event::ProjectEvent.new(action: :reopened, project_id: @org_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :reopened, v3[:action]
      assert_equal @org_project.id, v3[:project][:id]
      assert_equal @org_project.name, v3[:project][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
      assert_nil   v3[:changes]
    end

    test "when project is deleted" do
      event = Hook::Event::ProjectEvent.new(action: :deleted, project_id: @org_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_project.id, v3[:project][:id]
      assert_equal @org_project.name, v3[:project][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:repository]
    end
  end

  context "v3 org-owned repo project" do
    test "when project is created" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @org_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_repo_project.id, v3[:project][:id]
      assert_equal @org_repo_project.name, v3[:project][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project's name and body are updated" do
      event = Hook::Event::ProjectEvent.new(action: :edited, project_id: @org_repo_project.id, actor_id: @actor.id, changes: @changes)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @org_repo_project.id, v3[:project][:id]
      assert_equal @org_repo_project.name, v3[:project][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_equal "Body", v3[:changes][:body][:from]
      assert_equal "Name", v3[:changes][:name][:from]
      assert_nil   v3[:changes][:track_progress]
    end

    test "when project is closed" do
      event = Hook::Event::ProjectEvent.new(action: :closed, project_id: @org_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :closed, v3[:action]
      assert_equal @org_repo_project.id, v3[:project][:id]
      assert_equal @org_repo_project.name, v3[:project][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:changes]
    end

    test "when project is reopened" do
      event = Hook::Event::ProjectEvent.new(action: :reopened, project_id: @org_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :reopened, v3[:action]
      assert_equal @org_repo_project.id, v3[:project][:id]
      assert_equal @org_repo_project.name, v3[:project][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:changes]
    end

    test "when project is deleted" do
      event = Hook::Event::ProjectEvent.new(action: :deleted, project_id: @org_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_repo_project.id, v3[:project][:id]
      assert_equal @org_repo_project.name, v3[:project][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end
  end

  context "v3 user-owned repo project" do
    test "when project is created" do
      event = Hook::Event::ProjectEvent.new(action: :created, project_id: @user_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @user_repo_project.id, v3[:project][:id]
      assert_equal @user_repo_project.name, v3[:project][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
    end

    test "when project's name and body are updated" do
      event = Hook::Event::ProjectEvent.new(action: :edited, project_id: @user_repo_project.id, actor_id: @actor.id, changes: @changes)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @user_repo_project.id, v3[:project][:id]
      assert_equal @user_repo_project.name, v3[:project][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_equal "Body", v3[:changes][:body][:from]
      assert_equal "Name", v3[:changes][:name][:from]
      assert_nil   v3[:changes][:track_progress]
      assert_nil   v3[:organization]
    end

    test "when project is closed" do
      event = Hook::Event::ProjectEvent.new(action: :closed, project_id: @user_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :closed, v3[:action]
      assert_equal @user_repo_project.id, v3[:project][:id]
      assert_equal @user_repo_project.name, v3[:project][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
      assert_nil   v3[:changes]
    end

    test "when project is reopened" do
      event = Hook::Event::ProjectEvent.new(action: :reopened, project_id: @user_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :reopened, v3[:action]
      assert_equal @user_repo_project.id, v3[:project][:id]
      assert_equal @user_repo_project.name, v3[:project][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
      assert_nil   v3[:changes]
    end

    test "when project is deleted" do
      event = Hook::Event::ProjectEvent.new(action: :deleted, project_id: @user_repo_project.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @user_repo_project.id, v3[:project][:id]
      assert_equal @user_repo_project.name, v3[:project][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_nil   v3[:organization]
    end
  end
end
