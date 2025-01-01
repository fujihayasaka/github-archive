# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryWorkspaceTest < GitHub::TestCase
  fixtures do
    @actor = create(:user, plan: "free")
    @org = create(:organization, admin: @actor, plan: "free")
    @repo = create(:repository, owner: @org, from_example: :simple)

    @member = create(:user)
    @org.add_member(@member, action: :write)

    @advisory = create(:repository_advisory, repository: @repo, author: @actor)
    GitHub.context.push(actor_id: @actor.id)
    @workspace_repo = RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @actor).tap(&:save!)
  end

  context "#parent_advisory" do
    test "returns repository advisory if the repository is an advisory's workspace" do
      assert_equal @advisory, @workspace_repo.parent_advisory
    end
  end

  context "#parent_advisory_repository" do
    test "returns parent repo if the repository is an advisory's workspace" do
      assert_equal @repo, @workspace_repo.parent_advisory_repository
    end
  end

  context "#advisory_workspace?" do
    test "returns true if the repository is an advisory's workspace" do
      assert_predicate @workspace_repo, :advisory_workspace?
    end

    test "returns false if no repository advisory exists" do
      refute_predicate @repo, :advisory_workspace?
    end
  end

  context "#disabled_private?" do
    test "returns false for owners on free plan" do
      refute_predicate @workspace_repo, :disabled_private?
    end
  end

  context "organization default repository permissions" do
    test "grants admins permission" do
      @org.update_default_repository_permission(:read, actor: @actor)

      assert @workspace_repo.readable_by?(@actor)
      assert @workspace_repo.pushable_by?(@actor)
    end

    test "ignores the owners default repository permission" do
      @org.update_default_repository_permission(:read, actor: @actor)

      refute @workspace_repo.readable_by?(@member)
      refute @workspace_repo.pushable_by?(@member)
    end

    test "grants admins permission even when there's not default permission" do
      @org.update_default_repository_permission(:none, actor: @actor)

      assert @workspace_repo.readable_by?(@actor)
      assert @workspace_repo.pushable_by?(@actor)
    end

    test "grants admins permission when the default permission is updated" do
      @org.clear_default_repository_permission(actor: @actor)

      assert @workspace_repo.readable_by?(@actor)
      assert @workspace_repo.pushable_by?(@actor)
      refute @workspace_repo.readable_by?(@member)
      refute @workspace_repo.pushable_by?(@member)

      perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) { @org.update_default_repository_permission(:write, actor: @actor) }

      assert @workspace_repo.readable_by?(@actor)
      assert @workspace_repo.pushable_by?(@actor)
      refute @workspace_repo.readable_by?(@member)
      refute @workspace_repo.pushable_by?(@member)
    end
  end
end
