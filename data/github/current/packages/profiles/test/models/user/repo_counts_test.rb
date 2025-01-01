# typed: true
# frozen_string_literal: true

require "test_helper"

class UserRepoCountsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    @org_admin = create(:user)
    @org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@org_admin], seats: 20)
    @org2 = create(:organization, plan: GitHub::Plan.business_plus, admins: [@org_admin], seats: 20)
    if GitHub.single_business_environment?
      GitHub::Enterprise.ensure_business!
      @business = Business.first
      @org.update!(business: @business)
      @org2.update!(business: @business)
    else
      @business = create(:business, name: "Ian, Inc", owners: [@org_admin], organizations: [@org, @org2], seats: 20)
      @org.reload
      @org2.reload
    end
    @org.add_member(@user)
    @org.allow_private_repository_forking(actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @org_public_repo = create(:repository, name: "org-public-repo", owner: @org)
    @org_private_repo = create(:private_repository, name: "org-private-repo", owner: @org)
    @org_internal_repo = create(:private_repository, name: "org-internal-repo", owner: @org)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @org_internal_repo.set_visibility(actor: @org_admin, visibility: "internal") }
    @org_internal_repo.reload

    # Not referenced in a test but added deliberately to ensure it's correctly counted.
    org2_internal_repo = create(:private_repository, name: "org2-internal-repo", owner: @org2)
    org2_internal_repo.set_visibility(actor: @org_admin, visibility: "internal")

    @dummy_user_for_prefill = create(:user)
  end

  def assert_equal_for_single_and_prefill(expected, user, count_method)
    assert_equal expected, user.reload.repository_counts.public_send(count_method)
    GitHub::PrefillAssociations.prefill_batch_method([user, @dummy_user_for_prefill], :repository_counts)
    assert_equal expected, user.repository_counts.public_send(count_method)
  end

  test "total_repositories counts all repositories" do
    assert_equal_for_single_and_prefill(0, @user, :total_repositories)
    create(:repository, owner: @user)
    create(:private_repository, owner: @user)
    public_fork, status = @org_public_repo.fork(forker: @user)
    assert_equal_for_single_and_prefill(3, @user, :total_repositories)
  end

  test "public_repositories counts only user-owned public repositories" do
    assert_equal_for_single_and_prefill(0, @user, :public_repositories)

    create(:private_repository, owner: @user)
    assert_equal_for_single_and_prefill(0, @user, :public_repositories)

    create(:repository, owner: @user)
    assert_equal_for_single_and_prefill(1, @user, :public_repositories)
    create(:repository, owner: @user)
    assert_equal_for_single_and_prefill(2, @user, :public_repositories)
  end

  test "public_repositories counts public forks" do
    assert_equal_for_single_and_prefill(0, @user, :public_repositories)

    public_fork, status = @org_public_repo.fork(forker: @user)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @user, :public_repositories)

    private_fork, status = @org_private_repo.fork(forker: @user)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @user, :public_repositories)

    internal_fork, status = @org_internal_repo.fork(forker: @user)
    assert internal_fork, "Fork should have succeeded but failed with status '#{status}'"
    # Forks of internal repos are private
    assert_equal_for_single_and_prefill(1, @user, :public_repositories)
  end

  test "private_repositories counts only user-owned private repositories" do
    assert_equal_for_single_and_prefill(0, @user, :private_repositories)

    create(:repository, owner: @user)
    assert_equal_for_single_and_prefill(0, @user, :private_repositories)

    create(:private_repository, owner: @user)
    assert_equal_for_single_and_prefill(1, @user, :private_repositories)
    create(:private_repository, owner: @user)
    assert_equal_for_single_and_prefill(2, @user, :private_repositories)
  end

  test "private_repositories counts private forks" do
    assert_equal_for_single_and_prefill(0, @user, :private_repositories)

    private_fork, status = @org_private_repo.fork(forker: @user)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @user, :private_repositories)

    public_fork, status = @org_public_repo.fork(forker: @user)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @user, :private_repositories)

    internal_fork, status = @org_internal_repo.fork(forker: @user)
    assert internal_fork, "Fork should have succeeded but failed with status '#{status}'"
    # Forks of internal repos are private
    assert_equal_for_single_and_prefill(2, @user, :private_repositories)
  end

  test "owned_private_repositories counts only unlocked, user-owned private repositories" do
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)

    repo1 = create(:repository, owner: @user)
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)

    repo2 = create(:private_repository, owner: @user)
    assert_equal_for_single_and_prefill(1, @user, :owned_private_repositories)
    repo3 = create(:private_repository, owner: @user)
    assert_equal_for_single_and_prefill(2, @user, :owned_private_repositories)

    repo3.lock!
    assert_equal_for_single_and_prefill(1, @user, :owned_private_repositories)
    repo2.lock!
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)
  end

  test "owned_private_repositories does not count forks" do
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)

    private_fork, status = @org_private_repo.fork(forker: @user)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)

    public_fork, status = @org_public_repo.fork(forker: @user)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)

    internal_fork, status = @org_internal_repo.fork(forker: @user)
    assert internal_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @user, :owned_private_repositories)
  end

  test "internal_repositories counts all accessible internal repos" do
    assert_equal_for_single_and_prefill(2, @user, :internal_repositories)

    org_internal_repo = create(:private_repository, owner: @org)
    org_internal_repo.set_visibility(actor: @org_admin, visibility: "internal")
    assert_equal_for_single_and_prefill(3, @user, :internal_repositories)

    org2_internal_repo = create(:private_repository, owner: @org2)
    org2_internal_repo.set_visibility(actor: @org_admin, visibility: "internal")
    assert_equal_for_single_and_prefill(4, @user, :internal_repositories)
  end

  test "internal_repositories does not count forks" do
    assert_equal_for_single_and_prefill(2, @user, :internal_repositories)

    private_fork, status = @org_private_repo.fork(forker: @user)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(2, @user, :internal_repositories)

    public_fork, status = @org_public_repo.fork(forker: @user)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(2, @user, :internal_repositories)

    internal_fork, status = @org_internal_repo.fork(forker: @user)
    assert internal_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(2, @user, :internal_repositories)
  end

  test "disabled_repositories counts all disabled repos" do
    assert_equal_for_single_and_prefill(0, @user, :disabled_repositories)
    create(:repository, owner: @user, disabled_at: Time.now, disabling_reason: "reasons")
    assert_equal_for_single_and_prefill(1, @user, :disabled_repositories)
    create(:repository, owner: @user, disabled_at: Time.now, disabling_reason: "other reasons")
    assert_equal_for_single_and_prefill(2, @user, :disabled_repositories)
  end

  test "locked_repositories counts all locked repos" do
    assert_equal_for_single_and_prefill(0, @user, :locked_repositories)
    repo = create(:repository, owner: @user)
    repo.lock!(Repository::LockDependency::MOVING)
    assert_equal_for_single_and_prefill(1, @user, :locked_repositories)
    other_repo = create(:repository, owner: @user)
    other_repo.lock!(Repository::LockDependency::BILLING)
    assert_equal_for_single_and_prefill(2, @user, :locked_repositories)
  end
end
