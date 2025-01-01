# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationForkingARepositoryOwnedByAnOrganizationTest < GitHub::TestCase
  fixtures do
    @org       = create(:organization)
    @org.allow_private_repository_forking(actor: @org.admins.first, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @pullteam  = create(:team, organization: @org)
    @pushteam  = create :team, organization: @org, permission: "push"
    @puller    = create(:user)
    @pusher    = create(:user)
    @user2     = create(:user)
    @priv_repo = create(:private_repository, owner: @org)
    @pub_repo  = create(:repository, owner: @org)

    @pullteam.add_member @puller
    @pullteam.add_member @pusher
    @pullteam.add_repository @priv_repo, :pull
    @pullteam.add_repository @pub_repo, :pull
    @pushteam.add_member @pusher
    @pushteam.add_repository @priv_repo, :push

    @fork, @fork_reason = @priv_repo.fork(forker: @pusher)

    RepositoryAddTeamsJob.perform_now(@fork.id, @priv_repo.id)
  end

  test "resolves tenant in multi-tenant environment" do
    on_multi_tenant_enterprise do
      GitHub::CurrentTenant.remove
      assert_nil GitHub::CurrentTenant.get

      business = create :business, organizations: [@org]
      GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
      forked_repo, reason = @priv_repo.fork(forker: @puller)
      RepositoryAddTeamsJob.perform_now(forked_repo.id, @priv_repo.id)

      assert_equal business, GitHub::CurrentTenant.get
    end
  end

  test "works" do
    assert_difference "@puller.repositories.count" do
      @pub_repo.fork(forker: @puller)
    end
  end

  test "doesn't count against the org's plan" do
    assert_equal 1, @org.private_repo_count_for_limit_check
    assert_equal 0, @pusher.private_repo_count_for_limit_check
    assert_equal 2, @org.repositories.size
  end

  test "adds repo to all the parent's teams if the forker is in the org" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    forked_repo, reason = @priv_repo.fork(forker: @puller)
    RepositoryAddTeamsJob.perform_now(forked_repo.id, @priv_repo.id)

    assert_includes @pullteam.batched_repositories, forked_repo
    assert_includes @pushteam.batched_repositories.map(&:id), forked_repo.id

    assert_equal 1, GitHub.dogstats.increments("repository_add_teams_job.team_match", tags: ["success:true"]).size
  end

  test "increments team mismatch count for job if job fails" do
    GitHub.stubs(:dogstats).returns(GitHub::MemoryDogstatsD.new)
    # simulate some sort of failure
    Team.any_instance.stubs(:add_repository).returns(false)

    forked_repo, reason = @priv_repo.fork(forker: @puller)
    RepositoryAddTeamsJob.perform_now(forked_repo.id, @priv_repo.id)

    refute_includes @pullteam.batched_repositories, forked_repo
    refute_includes @pushteam.batched_repositories.map(&:id), forked_repo.id

    assert_equal 1, GitHub.dogstats.increments("repository_add_teams_job.team_match", tags: ["success:false"]).size
  end

  test "doesn't add the repo to any teams if the forker isn't in the org" do
    forked_repo, reason = @pub_repo.fork(forker: @user2)
    refute_includes @org.repositories, forked_repo
  end

  test "fails for those without pull access" do
    assert_no_difference "@user2.repositories.count" do
      @priv_repo.fork(forker: @user2)
    end
  end

  test "owners of a parent organization have access to foreign org-owned forks of private repos" do
    user = create(:user)
    @org.add_admin(user)
    @pullteam.add_member @user2 # give user2 read access to @repo

    secondary_org = create(:organization, business: @org.business)
    secondary_org.add_admin(@user2)

    forked_repo, reason = @priv_repo.fork(forker: @user2, org: secondary_org)

    assert forked_repo.pullable_by?(user), "forked repo should be pullable by a plan owner's owner"
  end

  test "owners of a parent organization have access to foreign user-owned forks of private repos" do
    user = create(:user)
    @org.add_admin(user)
    @pullteam.add_member @user2 # give user2 read access to @repo
    forked_repo, reason = @priv_repo.fork(forker: @user2)

    assert forked_repo.pullable_by?(user), "forked repo should be pullable by a plan owner's owner"
  end
end
