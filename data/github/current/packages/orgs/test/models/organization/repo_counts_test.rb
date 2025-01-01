# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationRepoCountsTest < GitHub::TestCase
  fixtures do
    @user = create(:user, login: "user")

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
    @org2.add_member(@user)
    @org2.allow_private_repository_forking(actor: @org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @org2_public_repo = create(:repository, name: "org2-public-repo", owner: @org2)
    @org2_private_repo = create(:private_repository, name: "org2-private-repo", owner: @org2)
    @org2_internal_repo = create(:private_repository, name: "org2-internal-repo", owner: @org2)
    perform_enqueued_jobs(only: [RepositoryOrchestrationJob]) { @org2_internal_repo.set_visibility(actor: @org_admin, visibility: "internal") }

    @advisory = create(:repository_advisory, :with_workspace, repository: @org2_public_repo)
    @advisory_workspace = @advisory.workspace_repository

    @dummy_org_for_prefill = create(:organization)
  end


  def assert_equal_for_single_and_prefill(expected, org, count_method)
    assert_equal expected, org.reload.repository_counts.public_send(count_method), "single count is incorrect"
    GitHub::PrefillAssociations.prefill_batch_method([org, @dummy_org_for_prefill], :repository_counts)
    assert_equal expected, org.repository_counts.public_send(count_method), "PrefillAssociations count is incorrect"
  end

  test "public_repositories counts only org-owned public repositories" do
    assert_equal_for_single_and_prefill(0, @org, :public_repositories)

    create(:private_repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(0, @org, :public_repositories)

    create(:repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(1, @org, :public_repositories)
    create(:repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(2, @org, :public_repositories)
  end

  test "public_repositories counts public forks" do
    assert_equal_for_single_and_prefill(0, @org, :public_repositories)

    public_fork, status = @org2_public_repo.fork(forker: @org_admin, org: @org)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @org, :public_repositories)

    private_fork, status = @org2_private_repo.fork(forker: @org_admin, org: @org)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @org, :public_repositories)

    # You can't fork an internal repo into an org, so we don't test that.
  end

  test "private_repositories counts only org-owned private repositories" do
    assert_equal_for_single_and_prefill(0, @org, :private_repositories)

    create(:repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(0, @org, :private_repositories)

    create(:private_repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(1, @org, :private_repositories)
    create(:private_repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(2, @org, :private_repositories)

    internal_repo = create(:private_repository, :minimal, name: "org-internal-repo", owner: @org)
    internal_repo.set_visibility(actor: @org_admin, visibility: "internal")
    assert_equal_for_single_and_prefill(2, @org, :private_repositories)
  end

  test "private_repositories does not count advisory workspace repos" do
    assert_equal_for_single_and_prefill(0, @org, :private_repositories)

    repo = create(:repository, :minimal, owner: @org)
    create(:repository_advisory, :with_workspace, repository: repo)
    assert_equal_for_single_and_prefill(0, @org, :private_repositories)
  end

  test "private_repositories counts private forks" do
    assert_equal_for_single_and_prefill(0, @org, :private_repositories)

    private_fork, status = @org2_private_repo.fork(forker: @org_admin, org: @org)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @org, :private_repositories)

    public_fork, status = @org2_public_repo.fork(forker: @org_admin, org: @org)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(1, @org, :private_repositories)

    # You can't fork an internal repo into an org, so we don't test that.
  end

  test "owned_private_repositories counts only unlocked, org-owned private repositories" do
    assert_equal_for_single_and_prefill(0, @org, :owned_private_repositories)

    repo1 = create(:repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(0, @org, :owned_private_repositories)

    repo2 = create(:private_repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(1, @org, :owned_private_repositories)
    repo3 = create(:private_repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(2, @org, :owned_private_repositories)

    repo3.lock!
    assert_equal_for_single_and_prefill(1, @org, :owned_private_repositories)
    repo2.lock!
    assert_equal_for_single_and_prefill(0, @org, :owned_private_repositories)
  end

  test "owned_private_repositories does not count forks" do
    assert_equal_for_single_and_prefill(0, @org, :owned_private_repositories)

    private_fork, status = @org2_private_repo.fork(forker: @org_admin, org: @org)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @org, :owned_private_repositories)

    public_fork, status = @org2_public_repo.fork(forker: @org_admin, org: @org)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @org, :owned_private_repositories)

    # You can't fork an internal repo into an org, so we don't test that.
  end

  test "internal_repositories counts only org-owned internal repos" do
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)

    create(:repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)
    create(:private_repository, :minimal, owner: @org)
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)

    org_internal_repo = create(:private_repository, :minimal, owner: @org)
    org_internal_repo.set_visibility(actor: @org_admin, visibility: "internal")
    assert_equal_for_single_and_prefill(1, @org, :internal_repositories)

    org2_internal_repo = create(:private_repository, :minimal, owner: @org2)
    org2_internal_repo.set_visibility(actor: @org_admin, visibility: "internal")
    assert_equal_for_single_and_prefill(1, @org, :internal_repositories)
  end

  test "internal_repositories does not count forks" do
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)

    private_fork, status = @org2_private_repo.fork(forker: @user)
    assert private_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)

    public_fork, status = @org2_public_repo.fork(forker: @user)
    assert public_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)

    internal_fork, status = @org2_internal_repo.fork(forker: @user)
    assert internal_fork, "Fork should have succeeded but failed with status '#{status}'"
    assert_equal_for_single_and_prefill(0, @org, :internal_repositories)
  end
end
