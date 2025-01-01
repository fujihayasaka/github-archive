# typed: true
# frozen_string_literal: true

require "test_helper"

require "test_helpers/dgit"

class RepositoryBizInternalForksForTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @biz_org_admin = create(:user)
    @biz_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org_admin], seats: 20)
    @biz_org2_admin = create(:user)
    @biz_org2 = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org2_admin], seats: 20)

    if GitHub.single_business_environment?
      @biz = Business.first
      @biz_org.update!(business: @biz)
      @biz_org2.update!(business: @biz)
    else
      @biz = create(:business,
        owners: [@biz_org_admin, @biz_org2_admin],
        organizations: [@biz_org, @biz_org2], seats: 20)
      @biz_org.reload
      @biz_org2.reload

      @biz2_org_admin = create(:user)
      @biz2_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz2_org_admin], seats: 20)
      @biz2_org2_admin = create(:user)
      @biz2_org2 = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz2_org2_admin], seats: 20)
      @biz2 = create(:business,
        owners: [@biz2_org_admin, @biz2_org2_admin],
        organizations: [@biz2_org, @biz2_org2], seats: 20)
      @biz2_org.reload
      @biz2_org2.reload
      @biz2_org.allow_private_repository_forking(actor: @biz2_org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      @biz2_org2.allow_private_repository_forking(actor: @biz2_org2_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

      @biz2_org_repo = create(:internal_repository, owner: @biz2_org)
      example_repo :repository_test_simple, @biz2_org_repo
    end

    @biz_org.allow_private_repository_forking(actor: @biz_org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @biz_org2.allow_private_repository_forking(actor: @biz_org2_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @biz_org_team = create(:team, organization: @biz_org)
    @biz_org_member = create(:user)
    @biz_org_team.add_member(@biz_org_member)

    @biz_org2_team = create(:team, organization: @biz_org2)
    @biz_org2_member = create(:user)
    @biz_org2_team.add_member(@biz_org2_member)

    @biz_org_repo = create(:internal_repository, owner: @biz_org)
    example_repo :repository_test_simple, @biz_org_repo
    @biz_org_team.add_repository(@biz_org_repo, :push)

    @biz_org2_repo = create(:internal_repository, owner: @biz_org2)
    example_repo :repository_test_simple, @biz_org2_repo
    @biz_org2_team.add_repository(@biz_org2_repo, :push)

    @biz_org_member_fork, status = @biz_org2_repo.fork(forker: @biz_org_member)
    assert @biz_org_member_fork, "Fork should have succeeded but failed with status '#{status}'"
    @biz_org2_member_fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
    assert @biz_org2_member_fork, "Fork should have succeeded but failed with status '#{status}'"
  end

  test "returns a user's forks of a business' internal repositories" do
    forks = Repository.biz_internal_forks_for(
              business: @biz, belonging_to_user: @biz_org2_member,
            )
    assert_equal 1, forks.count
    assert_includes forks, @biz_org2_member_fork
  end

  test "doesn't return other user's forks of a business' internal repositories" do
    user = create(:user)
    @biz_org2.add_member(user)
    user_fork, status = @biz_org_repo.fork(forker: user)
    assert user_fork, "Fork should have succeeded but failed with status '#{status}'"
    forks = Repository.biz_internal_forks_for(
              business: @biz, belonging_to_user: user,
            )
    assert_equal 1, forks.count
    assert_includes forks, user_fork

    forks = Repository.biz_internal_forks_for(
              business: @biz, belonging_to_user: @biz_org2_member,
            )
    assert_equal 1, forks.count
    refute_includes forks, user_fork
  end

  test "doesn't return user's other forks or repos" do
    forkable_public_repo = create(:repository, owner: @biz_org)
    forkable_private_repo = create(:private_repository, owner: @biz_org2)
    private_repo = create(:private_repository, owner: @biz_org2_member)
    public_repo = create(:repository, owner: @biz_org2_member)
    fork1, status = forkable_public_repo.fork(forker: @biz_org2_member)
    assert fork1, "Fork should have succeeded but failed with status '#{status}'"
    fork2, status = forkable_private_repo.fork(forker: @biz_org2_member)
    assert fork2, "Fork should have succeeded but failed with status '#{status}'"

    forks = Repository.biz_internal_forks_for(
              business: @biz, belonging_to_user: @biz_org2_member,
            )
    assert_equal 1, forks.count
    assert_includes forks, @biz_org2_member_fork
  end

  test "doesn't return forks from other businesses that belong to this user" do
    @biz2_org2.add_member(@biz_org2_member)
    assert_equal 2, @biz_org2_member.business_ids.count

    biz2_fork, status = @biz2_org_repo.fork(forker: @biz_org2_member)
    assert biz2_fork, "Fork should have succeeded but failed with status '#{status}'"

    forks = Repository.biz_internal_forks_for(
              business: @biz, belonging_to_user: @biz_org2_member,
            )
    assert_equal 1, forks.count
    assert_includes forks, @biz_org2_member_fork
    refute_includes forks, biz2_fork

    forks = Repository.biz_internal_forks_for(
              business: @biz2, belonging_to_user: @biz_org2_member,
            )
    assert_equal 1, forks.count
    assert_includes forks, biz2_fork
    refute_includes forks, @biz_org2_member_fork
  end unless GitHub.single_business_environment?

  test "forks of forks from internal fails" do
    user = create(:user)
    @biz_org2_member_fork.add_member(user)

    user_fork, status = @biz_org2_member_fork.fork(forker: user)
    refute user_fork, "Fork should not have succeeded"
    assert_equal status, :fork_of_internal
  end

  test "returns multiple forks from multiple orgs" do
    org_repo2 = create(:internal_repository, owner: @biz_org)
    org2_repo2 = create(:internal_repository, owner: @biz_org2)

    fork_biz_org2_repo, status = @biz_org2_repo.fork(forker: @biz_org2_member)
    assert fork_biz_org2_repo, "Fork should have succeeded but failed with status '#{status}'"
    fork_org_repo2, status = org_repo2.fork(forker: @biz_org2_member)
    assert org_repo2, "Fork should have succeeded but failed with status '#{status}'"
    fork_org2_repo2, status = org2_repo2.fork(forker: @biz_org2_member)
    assert fork_org2_repo2, "Fork should have succeeded but failed with status '#{status}'"

    forks = Repository.biz_internal_forks_for(
              business: @biz, belonging_to_user: @biz_org2_member,
            )
    assert_equal 4, forks.count
  end
end
