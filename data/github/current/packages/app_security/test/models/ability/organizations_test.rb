# typed: true
# frozen_string_literal: true

require "test_helper"

class AbilitiesRelatedToOrganizationsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)
    perform_enqueued_jobs(only: [SyncOrganizationDefaultRepositoryPermissionJob]) do
      @org  = create(:organization)
      @org.allow_private_repository_forking(actor: @org.admins.first, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      @org.update_default_repository_permission(:none, actor: @org.admins.first)
    end

    owner = @org.admins.first
    @repo = create(:private_repository, owner: @org)
    @team = create(:team, organization: @org)

    @org2 = create(:organization)
    @org2.allow_private_repository_forking(actor: @org2.admins.first)

    repo2 = create(:private_repository, owner: @org2)
    @org2.add_admin(owner)
    @org_fork, status = repo2.fork(forker: owner, org: @org)
    assert_equal :created, status

    @user_fork, status = @repo.fork(forker: owner)
    assert_equal :created, status
  end

  test "only allow grants to users" do
    ability = @org.send(:grant, @user, :read)
    assert_predicate ability, :persisted?

    assert_raises RuntimeError do
      @org.send(:grant, @org2, :read)
    end

    assert_raises RuntimeError do
      @org.send(:grant, @team, :read)
    end
  end

  test "include teams and repos owned by the org as dependents" do
    org3 = create(:organization)
    org_admin = @org.admins.first
    org3.add_admin org_admin
    org3_fork, status = @org_fork.fork(forker: org_admin, org: org3)
    assert_equal :created, status


    deps = @org.dependents

    assert deps.include? @repo
    assert deps.include? @org_fork
    assert deps.include? @user_fork
    assert deps.include? @team
    refute deps.include? org3_fork
  end

  test "cascade admin abilities to dependents" do
    @org.add_member @user, action: :admin
    assert_able @user, :admin, @repo
  end

  [:read, :write].each do |action|
    test "don't cascade #{action} abilities to dependents" do
      @org.add_member @user, action: action
      refute_able @user, action, @repo
    end
  end

  test "users with direct abilities on an org are direct org members" do
    direct_member = create(:user)
    @org.add_member direct_member
    assert @org.direct_member? direct_member
  end

  test "outside collaborators are not direct org members" do
    outside_collaborator = create(:user, login: "outside-collaborator")
    @repo.add_member(outside_collaborator)

    refute @org.direct_member?(outside_collaborator)
  end

  test "sync legacy user add to abilities" do
    refute @org.direct_member? @user

    @org.add_admin(@user)
    assert_able @user, :admin, @org
  end

  test "a user with admin on an org gets admin on a created org-owned repo" do
    owner = create(:user)
    org   = create(:organization, admin: owner)
    repo  = create(:repository, owner: org)

    assert_able owner, :admin, org
    assert_able owner, :admin, repo
  end

  test "a user with admin on an org loses admin on an org-owned repo after it's transferred" do
    old_owner = create(:user)
    old_org   = create(:organization, admin: old_owner)
    new_org   = create(:organization)
    new_owner = new_org.admins.first
    repo      = create(:repository, owner: old_org)
    repo.transfer_ownership_to new_org, actor: @user

    refute_able old_owner, :admin, repo
    assert_able new_owner, :admin, repo
  end

  test "removing a dependent repo removes inaccessible forks for org admins" do
    org = create(:organization, plan: "bronze")
    org.allow_private_repository_forking(actor: org.admins.first)
    repo = create(:private_repository, owner: org)
    fork = create(:fork_repository, forker: org.admins.first, fork_repo: repo)

    repo.update organization_id: nil, owner_id: @user.id
    org.dependent_removed repo.reload

    assert fork.reload.deleted?
  end
end
