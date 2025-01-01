# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectProjectLockTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create(:organization, plan: "silver").tap do |o|
      o.add_member(@owner, action: :admin)
    end
    @project = create(:project, owner: @org)
  end

  setup do
    GitHub.context.push(actor_id: @owner.id)
  end

  test "new projects are unlocked" do
    refute @project.locked?
  end

  test "allows more than one valid lock per project" do
    @project.lock!(lock_type: Project::ProjectLock::PROJECT_CLONING, actor: @owner)
    assert @project.locked_for?(Project::ProjectLock::PROJECT_CLONING)

    @project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
    assert @project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)
  end

  test "unlocking a single lock does not remove other locks" do
    @project.lock!(lock_type: Project::ProjectLock::PROJECT_CLONING, actor: @owner)
    @project.lock!(lock_type: Project::ProjectLock::NEW_PROJECT_IMPORT, actor: @owner)

    assert @project.locked_for?(Project::ProjectLock::PROJECT_CLONING)
    assert @project.locked_for?(Project::ProjectLock::NEW_PROJECT_IMPORT)

    @project.unlock(Project::ProjectLock::PROJECT_CLONING)
    refute @project.locked_for?(Project::ProjectLock::PROJECT_CLONING)
    assert @project.locked_for?(Project::ProjectLock::NEW_PROJECT_IMPORT)
  end

  Project::ProjectLock::LOCK_CONTEXT.keys.each do |lock_type|
    test "[LOCK TYPE: #{lock_type}] locked_for? returns true" do
      @project.lock!(lock_type: lock_type, actor: @owner)
      assert @project.locked_for?(lock_type)
    end

    test "[LOCK TYPE: #{lock_type}] set_job_context pushes the right context" do
      @project.set_job_context(lock_type)
      assert @project.job_context?(lock_type)
    end

    context "[LOCK TYPE: #{lock_type}] locked?" do
      test "true if any lock is present" do
        @project.lock!(lock_type: lock_type, actor: @owner)
        assert @project.locked?
      end

      test "false if no locks are present" do
        refute @project.locked?
      end
    end

    context "[LOCK TYPE: #{lock_type}] lock_safely" do
      test "locks, yields to a block, and unlocks the project" do
        refute @project.locked?
        Memex::KV.store.expects(:set).with(@project.lock_key(lock_type), @owner.login).once
        @project.lock_safely(lock_type: lock_type, actor: @owner) { "a block" }
        refute @project.locked?
      end
    end

    context "[LOCK TYPE: #{lock_type}] lock!" do
      test "locks for the provided reason" do
        refute @project.locked?
        @project.lock!(lock_type: lock_type, actor: @owner)
        assert @project.locked_for?(lock_type)
      end

      test "does not re-lock if already locked for the same reason" do
        @project.lock!(lock_type: lock_type, actor: @owner)
        assert @project.locked?

        lock_key = @project.lock_key(lock_type)
        Memex::KV.store.expects(:set).with(lock_key, @owner.login).never
        Memex::KV.store.expects(:del).with(lock_key).never

        @project.lock!(lock_type: lock_type, actor: @owner)
        assert Memex::KV.store.get(lock_key).value!
      end

      test "notifies subscribers of the lock by the actor" do
        locked_data = { name: @project.name, locked: @owner.login, project_migration: nil }

        channel = GitHub::WebSocket::Channels.project_metadata(@project)
        GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, locked_data).returns([]).once

        @project.lock!(lock_type: lock_type, actor: @owner)
      end
    end

    context "[LOCK TYPE: #{lock_type}] unlock" do
      test "unlocks" do
        @project.lock!(lock_type: lock_type, actor: @owner)
        assert @project.locked?

        @project.unlock(lock_type)
        refute @project.locked_for?(lock_type)
      end

      test "notifies subscribers of the unlock" do
        @project.lock!(lock_type: lock_type, actor: @owner)
        unlocked_data = { name: @project.name, locked: false, project_migration: nil }

        channel = GitHub::WebSocket::Channels.project_metadata(@project)
        GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, unlocked_data).returns([]).once

        @project.unlock(lock_type)
      end
    end

    context "[LOCK TYPE: #{lock_type}] job_context?" do
      test "true if context is present" do
        @project.lock!(lock_type: lock_type, actor: @owner)
        @project.set_job_context(lock_type)
        assert @project.job_context?(lock_type)
      end

      test "false if context is missing" do
        refute @project.job_context?(lock_type)
      end
    end
  end

  context "unlock!" do
    test "removes all valid locks" do
      @project.lock!(lock_type: Project::ProjectLock::PROJECT_CLONING, actor: @owner)
      @project.lock!(lock_type: Project::ProjectLock::CARD_ARCHIVING, actor: @owner)
      assert @project.locked_for?(Project::ProjectLock::PROJECT_CLONING)
      assert @project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)

      @project.unlock!
      refute @project.locked_for?(Project::ProjectLock::PROJECT_CLONING)
      refute @project.locked_for?(Project::ProjectLock::CARD_ARCHIVING)
    end

    test "notifies subscribers of the unlock" do
      locked_data = { name: @project.name, locked: @owner.login, project_migration: nil }
      unlocked_data = { name: @project.name, locked: false, project_migration: nil }

      channel = GitHub::WebSocket::Channels.project_metadata(@project)
      GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, locked_data).returns([]).once
      GitHub::WebSocket.expects(:notify_project_channel).with(@project, channel, unlocked_data).returns([]).once

      @project.lock!(lock_type: Project::ProjectLock::NEW_PROJECT_IMPORT, actor: @owner)
      @project.unlock!
    end
  end

  context "invalid lock reasons raise an error" do
    test "locked_for?" do
      assert_raises Project::ProjectLock::InvalidLockReasonError do
        @project.locked_for?("taco_break")
      end
    end

    test "lock!" do
      assert_raises Project::ProjectLock::InvalidLockReasonError do
        @project.lock!(lock_type: "taco_break", actor: @owner)
      end
    end

    test "unlock" do
      assert_raises Project::ProjectLock::InvalidLockReasonError do
        @project.unlock("taco_break")
      end
    end

    test "job_context?" do
      assert_raises Project::ProjectLock::InvalidLockReasonError do
        @project.job_context?("taco_break")
      end
    end

    test "set_job_context" do
      assert_raises Project::ProjectLock::InvalidLockReasonError do
        @project.set_job_context("taco_break")
      end
    end
  end
end
