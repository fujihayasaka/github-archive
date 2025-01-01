# typed: true
# frozen_string_literal: true

require "test_helper"

class HookPayloadProjectColumnPayloadTest < GitHub::TestCase
  fixtures do
    #org project
    @org_project     = create(:org_project)
    @org_project_col = create(:project_column,
      project: @org_project,
      created_at: "2016-01-03T16:00:49Z",
      updated_at: "2017-04-16T16:00:49Z",
    )
    @org             = @org_project.owner

    #org-owned repo project
    @org_repo             = create(:org_owned_repository, owner: @org)
    @org_repo_project     = create(:project, owner: @org_repo)
    @org_repo_project_col = create(:project_column, project: @org_repo_project)

    #user-owned repo project
    @user_repo_project     = create(:project)
    @user_repo_project_col = create(:project_column, project: @user_repo_project)
    @user_repo             = @user_repo_project.owner

    @actor = create(:user, login: "actor")
    @changes =  {
      old_name: "Name was here",
      name:     "Name doesn't get ad space",
    }
  end

  context "v3 org project" do
    test "when project column is created" do
      event = Hook::Event::ProjectColumnEvent.new(action: :created, project_column_id: @org_project_col.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_project_col.id, v3[:project_column][:id]
      assert_equal @org_project_col.name, v3[:project_column][:name]
      assert_equal "2016-01-03T16:00:49Z", v3[:project_column][:created_at]
      assert_equal "2017-04-16T16:00:49Z", v3[:project_column][:updated_at]
      assert_nil   v3[:repository]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project column's name is updated" do
      event = Hook::Event::ProjectColumnEvent.new(action: :edited, project_column_id: @org_project_col.id, actor_id: @actor.id, changes: @changes)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @org_project_col.id, v3[:project_column][:id]
      assert_equal @org_project_col.name, v3[:project_column][:name]
      assert_nil   v3[:repository]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_equal "Name was here", v3[:changes][:name][:from]
    end

    test "when project column is moved" do
      event = Hook::Event::ProjectColumnEvent.new(action: :moved, project_column_id: @org_project_col.id, actor_id: @actor.id, after_id: 6)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :moved, v3[:action]
      assert_equal @org_project_col.id, v3[:project_column][:id]
      assert_equal @org_project_col.name, v3[:project_column][:name]
      assert_equal 6, v3[:project_column][:after_id]
      assert_nil   v3[:repository]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project column is deleted" do
      event = Hook::Event::ProjectColumnEvent.new(action: :deleted, project_column_id: @org_project_col.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_project_col.id, v3[:project_column][:id]
      assert_equal @org_project_col.name, v3[:project_column][:name]
      assert_nil   v3[:repository]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end
  end

  context "v3 org-owned repo project" do
    test "when project column is created" do
      event = Hook::Event::ProjectColumnEvent.new(action: :created, project_column_id: @org_repo_project_col.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @org_repo_project_col.id, v3[:project_column][:id]
      assert_equal @org_repo_project_col.name, v3[:project_column][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project column's name is updated" do
      event = Hook::Event::ProjectColumnEvent.new(action: :edited, project_column_id: @org_repo_project_col.id, actor_id: @actor.id, changes: @changes)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @org_repo_project_col.id, v3[:project_column][:id]
      assert_equal @org_repo_project_col.name, v3[:project_column][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_equal "Name was here", v3[:changes][:name][:from]
    end

    test "when project column is moved" do
      event = Hook::Event::ProjectColumnEvent.new(action: :moved, project_column_id: @org_repo_project_col.id, actor_id: @actor.id, after_id: 4)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :moved, v3[:action]
      assert_equal @org_repo_project_col.id, v3[:project_column][:id]
      assert_equal @org_repo_project_col.name, v3[:project_column][:name]
      assert_equal 4, v3[:project_column][:after_id]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project column is deleted" do
      event = Hook::Event::ProjectColumnEvent.new(action: :deleted, project_column_id: @org_repo_project_col.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @org_repo_project_col.id, v3[:project_column][:id]
      assert_equal @org_repo_project_col.name, v3[:project_column][:name]
      assert_equal @org_repo.id, v3[:repository][:id]
      assert_equal @org_repo.name, v3[:repository][:name]
      assert_equal @org.id, v3[:organization][:id]
      assert_equal @org.login, v3[:organization][:login]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end
  end

  context "v3 user-owned repo project" do
    test "when project column is created" do
      event = Hook::Event::ProjectColumnEvent.new(action: :created, project_column_id: @user_repo_project_col.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :created, v3[:action]
      assert_equal @user_repo_project_col.id, v3[:project_column][:id]
      assert_equal @user_repo_project_col.name, v3[:project_column][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_nil   v3[:organization]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project column's name is updated" do
      event = Hook::Event::ProjectColumnEvent.new(action: :edited, project_column_id: @user_repo_project_col.id, actor_id: @actor.id, changes: @changes)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :edited, v3[:action]
      assert_equal @user_repo_project_col.id, v3[:project_column][:id]
      assert_equal @user_repo_project_col.name, v3[:project_column][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_nil   v3[:organization]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
      assert_equal "Name was here", v3[:changes][:name][:from]
    end

    test "when project column is moved" do
      event = Hook::Event::ProjectColumnEvent.new(action: :moved, project_column_id: @user_repo_project_col.id, actor_id: @actor.id, after_id: 2)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :moved, v3[:action]
      assert_equal @user_repo_project_col.id, v3[:project_column][:id]
      assert_equal @user_repo_project_col.name, v3[:project_column][:name]
      assert_equal 2, v3[:project_column][:after_id]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_nil   v3[:organization]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end

    test "when project column is deleted" do
      event = Hook::Event::ProjectColumnEvent.new(action: :deleted, project_column_id: @user_repo_project_col.id, actor_id: @actor.id)
      payload = Hook::Payload::ProjectColumnPayload.new(event)

      v3 = payload.to_hash

      assert_equal :deleted, v3[:action]
      assert_equal @user_repo_project_col.id, v3[:project_column][:id]
      assert_equal @user_repo_project_col.name, v3[:project_column][:name]
      assert_equal @user_repo.id, v3[:repository][:id]
      assert_equal @user_repo.name, v3[:repository][:name]
      assert_nil   v3[:organization]
      assert_equal @actor.id, v3[:sender][:id]
      assert_equal @actor.login, v3[:sender][:login]
    end
  end
end
