# typed: true
# frozen_string_literal: true

require "test_helper"
require "test_helpers/dgit"

class ExtractPrivateUserForkFromOrgTest < GitHub::TestCase

  fixtures do
    @user = create(:user, plan: "micro")
    @user_repo = create(:private_repository, owner: @user, from_example: :forkable)
    @user_repo.allow_private_repository_forking(actor: @user)
    @user2 = create(:user, plan: "micro")
    @user3 = create(:user, plan: "micro")
    @user_repo.add_member @user2
    @user_repo.add_member @user3
    @user2_fork = create(:fork_repository, fork_repo: @user_repo, forker: @user2)
    @user3_fork = create(:fork_repository, fork_repo: @user2_fork, forker: @user3)

    @org = create(:organization, plan: "bronze")
    @org.allow_private_repository_forking(actor: @org.admins.first)
    @org_repo = create(:private_repository, owner: @org, from_example: :forkable)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "removes the teams from the fork and all user-owned descendants" do
    @team = create(:team, organization: @org, permission: "push")
    @team.add_repository @org_repo, :push
    @user2 = create(:user, plan: "micro")
    @user3 = create(:user, plan: "micro")
    @other_user = create(:user)
    @team.add_member @user2
    @team.add_member @user3
    @team.add_member @other_user
    only = [RepositoryAddTeamsJob, RepositoryOrchestrationJob]
    @user2_fork, status = perform_enqueued_jobs(only: only) { @org_repo.fork(forker: @user2) }
    assert_equal :created, status
    @user2_fork.allow_private_repository_forking(actor: @user2)
    only = [RepositoryAddTeamsJob, RepositoryOrchestrationJob]
    @user3_fork, status = perform_enqueued_jobs(only: only) { @user2_fork.fork(forker: @user3) }
    assert_equal :created, status

    assert @user3_fork.pushable_by? @other_user
    assert @user3_fork.pushable_by? @user2

    assert @org_repo.pushable_by? @user2
    assert @org_repo.pushable_by? @user3
    assert @user2_fork.pushable_by? @other_user
    assert @user2_fork.pushable_by? @user3

    @user2_fork.extract!(synchronous: true)

    refute @user2_fork.reload.pushable_by? @other_user
    refute @user3_fork.reload.pushable_by? @other_user
    DGit.check_replicas @user2_fork
  end

  test "doesn't remove the teams from any org-owned descendants" do
    only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @org.admins.first) }

    @org2 = create(:organization)
    @org2.allow_private_repository_forking(actor: @org2.admins.first)
    @team = create(:team, organization: @org, permission: "pull")
    @team.add_repository @org_repo, :pull
    @other_team = create(:team, organization: @org2, permission: "pull")
    @user2 = create(:user, plan: "micro")
    @user3 = create(:user, plan: "micro")
    @other_user = create(:user)
    @org_user = create(:user)
    @other_org_user = create(:user)
    @team.add_member @user2
    @team.add_member @user3
    @team.add_member @other_user
    @org2.add_admin(@user3)
    @other_team.add_member @org_user
    @other_team.add_member @other_org_user
    only = [RepositoryAddTeamsJob, RepositoryOrchestrationJob]
    @user2_fork, status = perform_enqueued_jobs(only: only) { @org_repo.fork(forker: @user2) }
    assert_equal :created, status
    @user2_fork.allow_private_repository_forking(actor: @user2)

    only = [RepositoryOrchestrationJob]
    @org2_fork, status = perform_enqueued_jobs(only: only) { @user2_fork.fork(forker: @user3, org: @org2) }
    assert_equal :created, status
    @other_team.add_repository @org2_fork, :pull
    only = [RepositoryOrchestrationJob]
    @org_user_fork, status = perform_enqueued_jobs(only: only) { @org2_fork.fork(forker: @org_user) }
    assert_equal :created, status
    @other_team.add_repository @org_user_fork, :pull

    refute @org2_fork.pullable_by? @other_user
    assert @org2_fork.pullable_by? @org_user


    assert @org_repo.pullable_by? @user2
    assert @org_repo.pullable_by? @user3
    assert @user2_fork.pullable_by? @other_user
    assert @user2_fork.pullable_by? @user3

    @user2_fork.extract!(synchronous: true)

    assert @org_repo.reload.pullable_by? @user2
    assert @org_repo.pullable_by? @user3
    refute @user2_fork.reload.pullable_by? @other_user
    refute @user2_fork.pullable_by? @user3


    refute @org2_fork.reload.pullable_by? @other_user
    assert @org2_fork.pullable_by? @org_user
    assert @org_user_fork.reload.pullable_by? @other_org_user


    DGit.check_replicas @user2_fork
  end

  test "removes admin permissions granted via organization ownership" do
    only = [DeleteDependentAbilitiesJob, RemoveForksForInaccessibleRepositoriesJob, SyncOrganizationDefaultRepositoryPermissionJob]
    perform_enqueued_jobs(only: only) { @org.update_default_repository_permission(:none, actor: @org.admins.first) }

    team = create(:team, organization: @org, permission: "push")
    team.add_repository @org_repo, :push
    user = create(:user, plan: "micro")
    team.add_member user
    user_fork = create(:fork_repository, fork_repo: @org_repo, forker: user)

    assert user_fork.pullable_by?(@org.admins.first)
    assert_able @org.admins.first, :admin, user_fork

    user_fork.extract!(synchronous: true)
    user_fork.reload
    refute user_fork.in_organization?, "WTF"

    refute user_fork.pullable_by?(@org.admins.first)
    refute_able @org.admins.first, :admin, user_fork
    DGit.check_replicas user_fork
  end
end
