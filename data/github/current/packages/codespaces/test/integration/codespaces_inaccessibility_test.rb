# typed: true
# frozen_string_literal: true

require "test_helper"

class CodespacesInaccessibilityTest < GitHub::IntegrationTestCase

  fixtures do
    @repository = create(:repository)
    @private_repository = create(:private_repository)
    @user = create(:user)

    @org = create(:codespaces_organization)

    @team = create(:team, organization: @org)

    @org_repository = create(:repository, owner: @org)
    perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
      @org.update_default_repository_permission(:none, actor: @org)
      # For EMU test mode
      @repository.owner.update_default_repository_permission(:none, actor: @repository.owner) if @repository.owner.is_a?(Organization)
      @private_repository.owner.update_default_repository_permission(:none, actor: @private_repository.owner) if @private_repository.owner.is_a?(Organization)
    end
    @private_org_repository = create(:private_repository, owner: @org)

    @team.add_repository(@org_repository, :push)
    @team.add_repository(@private_org_repository, :push)
  end

  context "becomes readonly when repo push access but not visibility is lost", skip_enterprise: true do
    test "when a direct collaborator is removed from a user-owned repository", skip_with_all_emus: true do
      @repository.add_member_without_validation_or_notifications(@user)

      assert_codespace_becomes_readonly(@repository) do
        @repository.remove_member(@user)
      end
    end

    test "when an outside collaborator is removed from a public org-owned repository", skip_with_all_emus: true do
      assert @org_repository.add_member(@user)

      assert_codespace_becomes_readonly(@org_repository) do
        @org.remove_outside_collaborator!(@user)
      end
    end

    #emu user can't bill to users so will not be able to have a readonly codespace if removed from org
    test "when a user is removed from an org", skip_with_all_emus: true do
      @org.add_member(@user)
      assert @team.add_member(@user)

      assert_codespace_becomes_readonly(@org_repository, run_jobs: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        @org.remove_member(@user)
      end
    end

    test "when a user is removed from a team" do
      @org.add_member(@user)
      assert @team.add_member(@user)

      assert_codespace_becomes_readonly(@org_repository, run_jobs: [ClearTeamMembershipsJob]) do
        @team.remove_member(@user)
      end
    end

    test "when a repository is removed from a team" do
      @org.add_member(@user)
      assert @team.add_member(@user)

      assert_codespace_becomes_readonly(@org_repository, run_jobs: [ClearTeamMembershipsJob]) do
        @team.remove_repository(@org_repository)
      end
    end

    test "when a team is deleted" do
      @org.add_member(@user)
      assert @team.add_member(@user)

      assert_codespace_becomes_readonly(@org_repository, run_jobs: [DestroyTeamDependantsJob, ClearTeamMembershipsJob]) do
        @team.destroy
      end
    end
  end

  context "is deleted when repo push access and visibility are lost", skip_enterprise: true do
    test "when a public repository is deleted" do
      GitHub.flipper[:codespaces_pause_deletions_repository_removed].disable
      @repository.add_member_without_validation_or_notifications(@user)

      assert_codespace_is_deleted(@repository) do
        @repository.remove(@user, synchronous: true)
      end
    end

    test "when a public repository is made private for a non-collaborator" do
      GitHub.flipper[:codespaces_pause_deletions_repository_made_private].disable
      @repository.add_member_without_validation_or_notifications(@user) # Still need to do this to create codespace

      assert_codespace_is_deleted(@repository) do
        @repository.remove_member(@user)
        assert @repository.set_visibility(actor: create(:user), visibility: Repository::PRIVATE_VISIBILITY)
        perform_enqueued_jobs(only: RepositoryOrchestrationJob)
      end
    end

    context "private repositories" do
      test "when a direct collaborator is removed from a user-owned repository" do
        GitHub.flipper[:codespaces_pause_deletions_lost_repo_access].disable
        @private_repository.add_member_without_validation_or_notifications(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

        assert_codespace_is_deleted(@private_repository) do
          @private_repository.remove_member(@user)
        end
      end

      test "when an outside collaborator is removed from a public org-owned repository", skip_with_all_emus: true do
        GitHub.flipper[:codespaces_pause_deletions_lost_repo_access].disable
        assert @private_org_repository.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

        assert_codespace_is_deleted(@private_org_repository) do
          @org.remove_outside_collaborator!(@user)
        end
      end

      test "when a user is removed from an org" do
        GitHub.flipper[:codespaces_pause_deletions_lost_repo_access].disable
        @org.add_member(@user)
        assert @team.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

        assert_codespace_is_deleted(@private_org_repository, run_jobs: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
          @org.remove_member(@user)
        end
      end

      test "when a user is removed from a team" do
        GitHub.flipper[:codespaces_pause_deletions_lost_repo_access].disable
        @org.add_member(@user)
        assert @team.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

        assert_codespace_is_deleted(@private_org_repository, run_jobs: [ClearTeamMembershipsJob]) do
          @team.remove_member(@user)
        end
      end

      test "when a repository is removed from a team" do
        GitHub.flipper[:codespaces_pause_deletions_lost_repo_access].disable
        @org.add_member(@user)
        assert @team.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

        assert_codespace_is_deleted(@private_org_repository, run_jobs: [ClearTeamMembershipsJob]) do
          @team.remove_repository(@private_org_repository)
        end
      end

      test "when a team is deleted" do
        GitHub.flipper[:codespaces_pause_deletions_lost_repo_access].disable
        @org.add_member(@user)
        assert @team.add_member(@user)
        Codespaces::OrgPolicy.grant_billing_permission!(@user, @org)

        assert_codespace_is_deleted(@private_org_repository, run_jobs: [DestroyTeamDependantsJob, ClearTeamMembershipsJob]) do
          @team.destroy
        end
      end

    end
  end

  context "when access is preserved for the codespace creator", skip_enterprise: true do
    test "when a public repository is made private for a collaborator" do
      codespace = create(:codespace, repository: @repository, owner: @user)
      assert_predicate Codespace.where(id: codespace.id), :exists?

      perform_enqueued_jobs(only: [Codespaces::CleanUpInaccessibleJob, CodespacesDeleteJob]) do
        assert @repository.set_visibility(actor: create(:user), visibility: Repository::PRIVATE_VISIBILITY)
      end
      assert_predicate Codespace.where(id: codespace.id), :exists?
    end
  end

  def assert_codespace_is_deleted(repository, run_jobs: [], &block)
    # Don't automatically make the owner a collaborator on the codespace's
    # repository, we're gonna manually control access in these tests.
    if TestEnv.test_with_all_emus?
      codespace = create(:codespace, repository: repository, owner: @user, make_collaborator: false)
    else
      codespace = create(:codespace, repository: repository, owner: @user, make_collaborator: false, enable_org_access: false)
    end

    assert_predicate Codespace.where(id: codespace.id), :exists?
    FakeVSOServer.environments << { "id" => codespace.guid, "state" => Codespaces::Vscs::State::AVAILABLE }

    all_jobs = run_jobs.concat([Codespaces::CleanUpInaccessibleJob, CodespacesDeleteJob, CodespacesProcessSystemEventJob])
    perform_enqueued_jobs(only: all_jobs) do
      block.call
    end

    refute_predicate Codespace.where(id: codespace.id), :exists?
  end

  def assert_codespace_becomes_readonly(repository, run_jobs: [], &block)
    if TestEnv.test_with_all_emus?
      codespace = create(:codespace, repository: repository, owner: @user, make_collaborator: false)
    else
      codespace = create(:codespace, repository: repository, owner: @user, make_collaborator: false, enable_org_access: false)
    end
    assert_predicate Codespace.where(id: codespace.id), :exists?

    all_jobs = run_jobs.concat([Codespaces::CleanUpInaccessibleJob, CodespacesDeleteJob])

    perform_enqueued_jobs(only: all_jobs) do
      block.call
    end

    assert_predicate Codespace.where(id: codespace.id), :exists?

    repository_policy = Codespaces::RepositoryPolicy.async_with_prefill(@user, repository).sync
    assert_predicate repository_policy, :can_attempt_start?
    refute_predicate repository_policy, :can_push?
  end
end unless GitHub.enterprise?
