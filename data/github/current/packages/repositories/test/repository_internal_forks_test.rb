# typed: true
# frozen_string_literal: true

require "test_helper"

class InternalRepositoryForkRemovalTest < GitHub::TestCase
  fixtures do
    GitHub::Enterprise.ensure_business! if GitHub.single_business_environment?

    @biz_org_admin = create(:user)
    @biz_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org_admin], seats: 20)
    @biz_org.update_default_repository_permission(:none, actor: @biz_org_admin)
    @biz_org2_admin = create(:user)
    @biz_org2 = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org2_admin], seats: 20)

    if GitHub.single_business_environment?
      @biz = Business.first
      @biz_org.update!(business: @biz)
      @biz_org2.update!(business: @biz)
    else
      @biz = create(:business,
        name: "Ian, Inc",
        owners: [@biz_org_admin, @biz_org2_admin],
        organizations: [@biz_org, @biz_org2], seats: 20)
      @biz_org.reload
      @biz_org2.reload

      @biz2_org_admin = create(:user)
      @biz2_org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz2_org_admin], seats: 20)
      @biz2_org2_admin = create(:user)
      @biz2_org2 = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz2_org2_admin], seats: 20)
      @biz2 = create(:business,
        name: "Nathaniel, Inc",
        owners: [@biz2_org_admin, @biz2_org2_admin],
        organizations: [@biz2_org, @biz2_org2], seats: 20)
      @biz2_org.reload
      @biz2_org2.reload
      @biz2_org.allow_private_repository_forking(actor: @biz2_org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      @biz2_org2.allow_private_repository_forking(actor: @biz2_org2_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

      @biz2_org_repo = create(:internal_repository, name: "biz2-org-repo", owner: @biz2_org)
      example_repo :repository_test_simple, @biz2_org_repo
    end

    @biz_org.allow_private_repository_forking(actor: @biz_org_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
    @biz_org2.allow_private_repository_forking(actor: @biz_org2_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)

    @biz_org_team = create(:team, organization: @biz_org)
    @biz_org_member = create(:user, login: "biz-org-member")
    @biz_org_team.add_member(@biz_org_member)

    @biz_org2_team = create(:team, organization: @biz_org2)
    @biz_org2_member = create(:user, login: "biz-org2-member")
    @biz_org2_team.add_member(@biz_org2_member)

    @biz_org_repo = create(:internal_repository, name: "biz-org-repo", owner: @biz_org)
    example_repo :repository_test_simple, @biz_org_repo
    @biz_org_team.add_repository(@biz_org_repo, :push)

    @biz_org2_repo = create(:internal_repository, name: "biz-org2-repo", owner: @biz_org2)
    example_repo :repository_test_simple, @biz_org2_repo
    @biz_org2_team.add_repository(@biz_org2_repo, :push)
  end

  context "User removed from organization" do
    test "Removes fork of user removed from business" do
      # Fork by a user in another org that has access only because she's in the same biz
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      mailer_stub = stub("repo mailer")
      mailer_stub.expects(:deliver_later).once
      RepositoryMailer.expects(:private_fork_deleted).once.returns(mailer_stub)

      # Remove her from the org that associates her with the biz
      only = [RemoveBizUserForksJob, RemoveOrgMemberForksJob, RepositoryOrchestrationJob, RevokeOrgMembershipAbilitiesJob, BulkRemoveOrgMemberForksJob]
      perform_enqueued_jobs(only: only) { @biz_org2.remove_member!(@biz_org2_member) }

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
    end

    test "Do not duplicate DeleteRepositoryOrchestration" do
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)

      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      fork.remove(@biz_org2_member, synchronous: true)

      assert Repositories::Public.is_deleted?(fork.id)

      assert_no_difference("DeleteRepositoryOrchestration.count") do
        only = [RemoveBizUserForksJob, RemoveOrgMemberForksJob, RepositoryOrchestrationJob, RevokeOrgMembershipAbilitiesJob]
        perform_enqueued_jobs(only: only) { @biz_org2.remove_member!(@biz_org2_member) }
      end
    end

    test "Removes multiple forks from multiple business orgs" do
      biz_org3_admin = create(:user)
      biz_org3 = create(:organization, plan: GitHub::Plan.business_plus, admins: [biz_org3_admin], seats: 20, business: @biz)
      biz_org3.allow_private_repository_forking(actor: biz_org3_admin, policy: Configurable::AllowPrivateRepositoryForking::ENTERPRISE_ORGANIZATIONS_USER_ACCOUNTS)
      biz_org3_repo = create(:internal_repository, name: "biz-org3-repo", owner: biz_org3)
      example_repo :repository_test_simple, biz_org3_repo

      biz_org_repo2 = create(:internal_repository, name: "biz-org-repo2", owner: @biz_org)
      example_repo :repository_test_simple, biz_org_repo2

      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"
      fork2, status = @biz_org2_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"
      fork3, status = biz_org_repo2.fork(forker: @biz_org2_member)
      assert fork3, "Fork should have succeeded but failed with status '#{status}'"
      fork4, status = biz_org3_repo.fork(forker: @biz_org2_member)
      assert fork4, "Fork should have succeeded but failed with status '#{status}'"

      # Remove from the org that associates user with the biz
      only = [RemoveBizUserForksJob, RemoveOrgMemberForksJob, RepositoryOrchestrationJob, RevokeOrgMembershipAbilitiesJob, BulkRemoveOrgMemberForksJob]
      perform_enqueued_jobs(only: only) { @biz_org2.remove_member!(@biz_org2_member) }

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_deleted?(fork2.id), "Private fork should be deleted"
      assert Repositories::Public.is_deleted?(fork3.id), "Private fork should be deleted"
      assert Repositories::Public.is_deleted?(fork4.id), "Private fork should be deleted"
    end

    test "Does not remove forks from user's other business" do
      @biz2_org2.add_member(@biz_org2_member)

      # Fork in business 1
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork in first business should have succeeded but failed with status '#{status}'"
      # Fork in business 2
      fork2, status = @biz2_org_repo.fork(forker: @biz_org2_member)
      assert fork2, "Fork in second business should have succeeded but failed with status '#{status}'"

      # Remove from business 1
      only = [RemoveBizUserForksJob, RemoveOrgMemberForksJob, RepositoryOrchestrationJob, RevokeOrgMembershipAbilitiesJob, BulkRemoveOrgMemberForksJob]
      perform_enqueued_jobs(only: only) { @biz_org2.remove_member!(@biz_org2_member) }

      assert Repositories::Public.is_deleted?(fork.id), "Private fork from first business should be deleted"
      assert Repositories::Public.is_active?(fork2.id), "Private fork from second business should not be deleted"
    end unless GitHub.single_business_environment?

    test "Does not remove forks of user not removed from business" do
      # Fork by a user in another org that has access only because she's in the same biz
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      # Fork of another user in the biz
      fork2, status = @biz_org_repo.fork(forker: @biz_org_member)
      assert fork2, "Fork should have succeeded but failed with status '#{status}'"

      # Remove first user from the org that associates her with the biz
      only = [RemoveBizUserForksJob, RemoveOrgMemberForksJob, RepositoryOrchestrationJob, RevokeOrgMembershipAbilitiesJob, BulkRemoveOrgMemberForksJob]
      perform_enqueued_jobs(only: only) { @biz_org2.remove_member!(@biz_org2_member) }

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_active?(fork2.id), "Private fork2 should not be deleted"
    end

    test "Does not remove forks if user is still associated with business" do
      # Associate the user with the business via another org
      org = create(:organization, plan: GitHub::Plan.business_plus, admins: [@biz_org_admin], seats: 20)
      org.update!(business: @biz)
      org.reload
      org.add_member(@biz_org2_member)

      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      # Still associate with biz through org, so the fork should stay
      perform_enqueued_jobs(only: [RevokeOrgMembershipAbilitiesJob]) { @biz_org2.remove_member!(@biz_org2_member) }
      assert Repositories::Public.is_active?(fork.id), "Private fork should not be deleted"

      # Remove from last org tying to biz. NOW the fork should be deleted.
      only = [RemoveBizUserForksJob, RemoveOrgMemberForksJob, RepositoryOrchestrationJob, RevokeOrgMembershipAbilitiesJob, BulkRemoveOrgMemberForksJob]
      perform_enqueued_jobs(only: only) { org.remove_member!(@biz_org2_member) }
      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
    end

    test "Does not remove internal repos that are still accessible due to multiple org memberships" do
      org_fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert org_fork, "Fork should have succeeded but failed with status '#{status}'"
      org2_fork, status = @biz_org2_repo.fork(forker: @biz_org2_member)
      assert org2_fork, "Fork should have succeeded but failed with status '#{status}'"

      @biz_org.add_member(@biz_org2_member)
      @biz_org2.remove_member!(@biz_org2_member)

      assert Repositories::Public.is_active?(org_fork.id), "Fork should not be deleted"
      assert Repositories::Public.is_active?(org2_fork.id), "Fork2 should not be deleted"
    end
  end

  context "User removed directly from business" do
    test "Removes forks of billing manager removed from business" do
      billing_manager = create(:user)
      @biz.billing.add_manager billing_manager, actor: @biz_org_admin

      fork, status = @biz_org_repo.fork(forker: billing_manager)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"
      fork2, status = @biz_org2_repo.fork(forker: billing_manager)
      assert fork2, "Fork should have succeeded but failed with status '#{status}'"

      only = [RemoveBizUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) do
        @biz.billing.remove_manager(billing_manager, actor: @biz_org_admin, reason: "so unprofesh")
      end

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_deleted?(fork2.id), "Private fork2 should be deleted"
    end unless GitHub.single_business_environment? # single_business_environments have no billing managers

    test "Removes forks of administrator removed from business" do
      biz_admin = create(:user)
      @biz.add_owner biz_admin, actor: @biz_org_admin

      fork, status = @biz_org_repo.fork(forker: biz_admin)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"
      fork2, status = @biz_org2_repo.fork(forker: biz_admin)
      assert fork2, "Fork should have succeeded but failed with status '#{status}'"

      only = [RemoveBizUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) do
        @biz.remove_owner(biz_admin, actor: @biz_org_admin, reason: "so unprofesh")
      end

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_deleted?(fork2.id), "Private fork2 should be deleted"
    end unless GitHub.single_business_environment?
  end

  context "Internal repository changed to private" do
    test "Deletes fork of same-org user who no longer has permission" do
      biz_org_member2 = create(:user)
      @biz_org.add_member(biz_org_member2)

      fork, status = @biz_org_repo.fork(forker: biz_org_member2)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      only = [RemoveInvalidUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private") }

      refute @biz_org_repo.pullable_by?(biz_org_member2)
      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_active?(@biz_org_repo.id)
    end

    test "Does not delete fork of same-org user who is a collaborator on root" do
      biz_org_member2 = create(:user)
      @biz_org.add_member(biz_org_member2)
      @biz_org_repo.add_member(biz_org_member2)

      fork, status = @biz_org_repo.fork(forker: biz_org_member2)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private")

      assert Repositories::Public.is_active?(fork.id)
      assert Repositories::Public.is_active?(@biz_org_repo.id)
    end

    test "Does not delete fork of same-org user who has permission via team membership" do
      fork, status = @biz_org_repo.fork(forker: @biz_org_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private")

      assert Repositories::Public.is_active?(fork.id)
      assert Repositories::Public.is_active?(@biz_org_repo.id)
    end

    test "Deletes fork of user in another org who no longer has permission" do
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      only = [RemoveInvalidUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private") }

      refute @biz_org_repo.pullable_by?(@biz_org2_member)
      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_active?(@biz_org_repo.id)
    end

    test "Does not delete fork of user in another org who has been added as a collaborator" do
      @biz_org_repo.add_member(@biz_org2_member)
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private")

      assert @biz_org_repo.pullable_by?(@biz_org2_member)
      assert Repositories::Public.is_active?(fork.id)
      assert Repositories::Public.is_active?(@biz_org_repo.id)
    end

    test "Does not delete fork of fork, reparents correctly, when its owner retains access to network root" do
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"
      fork.add_member(@biz_org_member)

      # Temporarily change the visibility on the root Repo to allow the now unsupported 2-level internal fork creation
      @biz_org_repo.send(:set_permission, Repository::PRIVATE_VISIBILITY)
      fork_of_fork, status = fork.fork(forker: @biz_org_member)
      assert fork_of_fork, "Fork should have succeeded but failed with status '#{status}'"
      @biz_org_repo.send(:set_permission, Repository::INTERNAL_VISIBILITY)
      assert_equal  @biz_org_repo.internal?, true

      only = [RemoveInvalidUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private") }

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_active?(@biz_org_repo.id)

      assert @biz_org_repo.pullable_by?(@biz_org_member)
      assert Repositories::Public.is_active?(fork_of_fork.id)

      fork_of_fork.reload
      assert_equal @biz_org_repo.id, fork_of_fork.parent_id
    end

    test "Deletes fork of fork when its owner loses access to network root" do
      fork, status = @biz_org_repo.fork(forker: @biz_org_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"
      fork.add_member(@biz_org2_member)

      # Temporarily change the visibility on the root Repo to allow the now unsupported 2-level internal fork creation
      @biz_org_repo.send(:set_permission, Repository::PRIVATE_VISIBILITY)
      fork_of_fork, status = fork.fork(forker: @biz_org2_member)
      assert fork_of_fork, "Fork should have succeeded but failed with status '#{status}'"
      @biz_org_repo.send(:set_permission, Repository::INTERNAL_VISIBILITY)
      assert_equal @biz_org_repo.internal?, true

      only = [RemoveInvalidUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private") }

      assert Repositories::Public.is_active?(@biz_org_repo.id)
      assert Repositories::Public.is_active?(fork.id)

      assert Repositories::Public.is_deleted?(fork_of_fork.id), "Private fork should be deleted"
    end

    test "Deletes nested forks when all owners lose access to network root" do
      assert_equal "internal", @biz_org_repo.visibility
      fork, status = @biz_org_repo.fork(forker: @biz_org2_member)
      assert fork, "Fork should have succeeded but failed with status '#{status}'"

      biz_org2_member2 = create(:user)
      @biz_org2_team.add_member(biz_org2_member2)
      fork.add_member(biz_org2_member2)

      # Temporarily change the visibility on the root Repo to allow the now unsupported 2-level internal fork creation
      @biz_org_repo.send(:set_permission, Repository::PRIVATE_VISIBILITY)
      fork_of_fork, status = fork.fork(forker: biz_org2_member2)
      assert fork_of_fork, "Fork should have succeeded but failed with status '#{status}'"
      @biz_org_repo.send(:set_permission, Repository::INTERNAL_VISIBILITY)
      assert_equal @biz_org_repo.internal?, true

      only = [RemoveInvalidUserForksJob, RepositoryOrchestrationJob]
      perform_enqueued_jobs(only: only) { assert @biz_org_repo.set_visibility(actor: @biz_org_admin, visibility: "private") }

      assert Repositories::Public.is_deleted?(fork.id), "Private fork should be deleted"
      assert Repositories::Public.is_deleted?(fork_of_fork.id), "Private fork should be deleted"
    end
  end
end
