# typed: true
# frozen_string_literal: true

require "test_helper"

class AbilitiesRelatedToRepositoriesTest < GitHub::TestCase
  fixtures do
    @actor    = create(:user)

    @org            = create(:organization)
    @org_owned_repo = create(:repository, owner: @org, from_example: :simple)
    @org_admin1     = @org.admins.first
    @team           = create(:team, organization: @org)
    @team.add_repository @org_owned_repo, :pull
    @org_admin2     = create(:user, login: "org-admin2")
    @org.add_admin(@org_admin2)
    @org.allow_private_repository_forking(actor: @org_admin1, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @owner           = create(:user)
    @repo            = create(:repository, owner: @owner, from_example: :simple)
    @user            = create(:user)
    @user_owned_repo = create(:repository, owner: @user, from_example: :simple)

    @transfer_receiving_org  = create(:organization)
    @transfer_receiving_user = create(:user)
    @forking_org             = create(:organization)
    @forking_user            = create(:user)

    example_repo_snapshot
  end

  setup do
    example_repo_restore
  end

  test "the repo's owner can do anything" do
    assert_able @repo.owner, :admin, @repo
  end

  test "anybody can read a public repository" do
    assert_able @user, :read, @repo
    refute_able @user, :write, @repo
  end

  test "even a nil can read a public repository" do
    assert_able nil, :read, @repo
  end

  test "transferring a repo from one user to another user" do
    @user_owned_repo.add_member @actor # add a collaborator

    assert @user_owned_repo.transfer_ownership_to @transfer_receiving_user, actor: @user

    assert_equal_owner @transfer_receiving_user, @user_owned_repo.owner
    assert_able @transfer_receiving_user, :admin, @user_owned_repo
    refute_able @user, :admin, @user_owned_repo
    assert_able @actor, :write, @user_owned_repo, "collaborators should be preserved"
  end

  test "transferring a repo from a user to an org" do
    @user_owned_repo.add_member @actor # add a collaborator
    @user_owned_repo.transfer_ownership_to @transfer_receiving_org, actor: @user

    assert_equal_owner @transfer_receiving_org, @user_owned_repo.owner

    assert_able @transfer_receiving_org.admins.first, :admin, @user_owned_repo
    refute_able @user, :admin, @user_owned_repo
  end

  test "transferring a repo from a user to an org that the user is a member of" do
    @team.add_member @user
    @user_owned_repo.transfer_ownership_to @transfer_receiving_org, actor: @user

    assert_equal_owner @transfer_receiving_org, @user_owned_repo.owner
    assert_able @transfer_receiving_org.admins.first, :admin, @user_owned_repo
    # TODO @github/abilities allow this again once domain model has settled
    # assert_able @user, :admin, @user_owned_repo, "user should retain admin"
  end

  test "transferring a repo from an org to a user" do
    @team.add_member @user

    @org_owned_repo.transfer_ownership_to @transfer_receiving_user, actor: @actor

    assert_equal_owner @transfer_receiving_user, @org_owned_repo.owner
    assert_able @transfer_receiving_user, :admin, @org_owned_repo
    refute_able @org_admin1, :admin, @org_owned_repo
    refute_able @user, :write, @org_owned_repo, "collaborators should be cleared"
  end

  test "forking a public repo from one user to another user" do
    @repo.add_member @actor

    forked = create(:fork_repository, forker: @forking_user, fork_repo: @repo)
    assert forked

    assert_able @forking_user, :admin, forked
    refute_able @owner, :write, forked, "shouldn't give repo owner write on public forks"
    refute_able @actor, :write, forked, "should not preserve collaborators"
  end

  test "forking a public repo from user to user shouldn't grant anything" do
    owner = create(:user)
    repo = create(:public_repository, owner: owner, from_example: :simple)
    forker = create(:user)
    fork = create(:fork_repository, forker: forker, fork_repo: repo)

    assert_able forker, :admin, fork
    refute_able owner, :admin, fork
    refute_able owner, :write, fork
    assert_empty Ability.grants(fork)
  end

  test "forking a public repo from a user to an org" do
    @repo.add_member @actor

    @forking_org.add_admin(@forking_user) # add user to org

    forked = create(:fork_repository, forker: @forking_user, fork_repo: @repo, organization: @forking_org)
    assert forked

    assert_able @forking_user, :admin, forked, "new owner should have admin"
    refute_able @actor, :write, forked, "should not preserve collaborators"
  end

  test "forking a public repo from an org to a user" do
    @org_owned_repo.add_member @actor

    # public org-owned repo forked by a user
    forked = create(:fork_repository, forker: @forking_user, fork_repo: @org_owned_repo)
    assert forked

    # fork owner has admin access
    assert_able @forking_user, :admin, forked

    # parent org admins do not have access
    refute_able @org_admin1, :write, forked, "shouldn't give org admins write on public forks"
    # parent org members should not have access
    refute_able @actor, :write, forked, "should not preserve collaborators"
  end

  test "forking a public repo from one org to another org" do
    @org_owned_repo.add_member @actor

    @forking_org.add_admin(@forking_user) # add user to org

    forked = create(:fork_repository, forker: @forking_user, fork_repo: @org_owned_repo, organization: @forking_org)
    assert forked

    assert_able @forking_user, :admin, forked
    refute_able @actor, :write, forked, "should not preserve collaborators"

    @org.admins.each do |admin|
      refute_able admin, :admin, forked, "fork's parent org admins don't retain admin on fork of public repo into new org"
    end
  end

  test "forking a private repo from one user to another user" do
    @repo.update_attribute :private, true

    assert @repo.add_member(@user)

    forked = create(:fork_repository, forker: @user, fork_repo: @repo)
    assert forked

    assert_able @user, :admin, forked
    refute_able @repo.plan_owner, :admin, forked, "shouldn't allow source's plan owner to admin fork"
    assert_able @repo.plan_owner, :write, forked, "should allow source's plan owner to write fork"
    refute_equal @user, @repo.plan_owner, "forker should not be source owner"
  end

  test "forking a private repo from a user to an org" do
    @user_owned_repo.update_attribute :private, true
    assert @user_owned_repo.add_member(@forking_user)

    @user_owned_repo.add_member @actor # add a collaborator

    new_admin = create(:user)
    @forking_org.add_admin(new_admin) # add new user to org as admin
    @forking_org.add_admin(@forking_user) # add forking user to org as admin

    forked = create(:fork_repository, forker: @forking_user, fork_repo: @user_owned_repo, organization: @forking_org)
    assert forked

    assert_able @forking_user, :admin, forked
    # verify all admins have access not just the one that forked repo
    assert_able new_admin, :admin, forked
    refute_able @user, :admin, forked, "shouldn't allow source's plan owner to admin fork"
    refute_able @user, :write, forked, "shouldn't allow source's plan owner to write fork"
    refute_able @actor, :write, forked, "should not preserve collaborators"

    new_user = create(:user, plan: "small")
    @user_owned_repo.transfer_ownership_to(new_user, actor: @user)
    forked.reload
    refute_able new_user, :write, forked, "shouldn't allow new source owner to write forks after a transfer"
    refute_able new_user, :admin, forked, "shouldn't allow new source owner to admin forks after a transfer"
  end

  test "repository#owning_org_id fork org-owned repo to user then transfer parent repo" do
    # no forks yet
    assert_equal @org.id, @org_owned_repo.owning_organization_id
    refute @user_owned_repo.owning_organization_id

    # fork org-owned repo
    @org_owned_repo.update_attribute :private, true
    readers = create :team, organization: @org, permission: "pull"
    readers.add_repository @org_owned_repo, :pull
    readers.add_member @forking_user
    forked, status = @org_owned_repo.fork forker: @forking_user
    # parent repo's org still has administrative privileges on fork
    assert_equal @org.id, forked.owning_organization_id
    assert_equal :created, status

    # transfer ownership of parent repo
    new_org = create(:organization, plan: "silver")
    new_org_admin = new_org.admins.first
    new_org.add_admin(@forking_user)
    @org_owned_repo.transfer_ownership_to(new_org, actor: @actor)
    # new owning org of parent repo now has administrative privileges
    assert_equal new_org.id, @org_owned_repo.owning_organization_id
    assert_equal new_org.id, forked.owning_organization_id
  end

  test "repository#owning_org_id org-owned repo forked to another org" do
    @org_owned_repo.update_attribute :private, true

    readers = create :team, organization: @org, permission: "pull"
    readers.add_repository @org_owned_repo, :pull
    readers.add_member @forking_user

    forking_org_admin = create(:user)
    @forking_org.add_admin(forking_org_admin)
    @forking_org.add_admin(@forking_user)

    forked = create(:fork_repository, forker: @forking_user, fork_repo: @org_owned_repo, organization: @forking_org)
    assert forked

    # fork's org owner has administrative rights, not the fork's parent org
    assert_equal @forking_org.id, forked.owning_organization_id
  end

  test "forking a private repo from an org to a user, and then transferring fork's parent" do
    @org_owned_repo.update_attribute :private, true

    readers = create :team, organization: @org, permission: "pull"
    readers.add_repository @org_owned_repo, :pull
    readers.add_member @forking_user
    readers.add_member @user

    forked, status = @org_owned_repo.fork forker: @forking_user
    assert_equal :created, status

    assert_able @forking_user, :admin, forked
    assert_able @org_admin1, :admin, forked, "should allow org admins to still admin the fork"
    assert_able @org_admin2, :admin, forked, "should allow org admins to still admin the fork"
    assert_able @user, :read, forked, "should preserve team collaborators"

    new_admin = create(:user)
    @org.add_member new_admin, action: :admin
    assert_able new_admin, :admin, forked, "should allow future org admins to admin the fork"

    new_org       = create(:organization, plan: "silver")
    new_org_admin = new_org.admins.first
    new_org.add_admin(@forking_user)

    @org_owned_repo.transfer_ownership_to(new_org, actor: @actor)

    # since the forked repo is already loaded in memory, the data changed during the
    # org transfer will not be reflected in the object unless we reload the repo from the db
    forked.reload

    assert_able new_org_admin, :admin, forked, "should allow admins on the new org to admin the fork after a transfer"

    # org admins from prior owning org (pre-transfer) should no longer have
    # access to fork
    refute_able @org_admin1, :admin, forked
    refute_able @org_admin2, :admin, forked

    assert_equal forked.parent_id, @org_owned_repo.id
    assert_equal new_org.id, @org_owned_repo.owner_id
    assert_equal new_org.id, @org_owned_repo.organization_id
    assert_equal forked.organization_id, new_org.id
  end

  test "forking a private repo from one org to another org" do
    @org_owned_repo.update_attribute :private, true

    readers = create :team, organization: @org, permission: "pull"
    readers.add_repository @org_owned_repo, :pull
    readers.add_member @forking_user

    forking_org_admin = create(:user)
    @forking_org.add_admin(forking_org_admin)
    @forking_org.add_admin(@forking_user)

    forked = create(:fork_repository, forker: @forking_user, fork_repo: @org_owned_repo, organization: @forking_org)
    assert forked

    # admins of org that repo was forked into have admin access
    assert_able @forking_user, :admin, forked, "via custom Repository#can?"
    assert_able forking_org_admin, :admin, forked, "via grant_abilities_for_owning_org"

    # admins of org that repo was from from no longer have admin access
    refute_able @org_admin1, :admin, forked, "shouldn't allow org admins to still admin the fork"
    refute_able @org_admin2, :admin, forked, "shouldn't allow org admins to still admin the fork"
    refute_able @actor, :write, forked, "should not preserve collaborators"

    new_admin = create(:user)
    @forking_org.add_member new_admin, action: :admin
    assert_able new_admin, :admin, forked, "new admins added to a fork's owning org can admin fork"

    new_org_admin = create(:user)
    @org.add_member new_org_admin, action: :admin
    refute_able new_org_admin, :admin, forked, "shouldn't allow future org admins to admin fork"
  end

  test "sync add_member to abilities" do
    refute_able @actor, :write, @repo

    @repo.add_member @actor
    assert_able @actor, :write, @repo
  end

  test "sync remove_member to abilitites" do
    @repo.add_member @actor
    assert_able @actor, :write, @repo

    @repo.remove_member @actor
    refute_able @actor, :write, @repo
  end
end
