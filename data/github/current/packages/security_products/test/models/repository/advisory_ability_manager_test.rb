# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryAbilityManagerTest < GitHub::TestCase
  fixtures do
    @owner = create(:paid_user, login: "owner")
    @collab = create(:user, login: "collab")
    @rando = create(:user, login: "rando")

    @org   = create(:organization, login: "acme", admin: @owner)
    @admin = create(:user, login: "admin-user")
    @org.add_admin(@admin)

    @collab_team = create(:team, name: "collaborators",  organization: @org)
    @other_team = create(:team, name: "other", organization: @org)

    @repository = create(:private_repository, name: "acme", owner: @org)
    enable_feature_flag(:advisory_db_unrestorable_repositories, @repository)
    @public_repo = create(:repository, name: "acme-public", owner: @org)

    @repository.add_member(@collab, action: :admin)
    @repository.add_team(@collab_team, action: :admin)

    only = [WorkspaceAbilitySetupJob]
    perform_enqueued_jobs(only: only) do
      # Create an open advisory without a workspace
      @open_advisory_only = create(:repository_advisory, repository: @repository)
      assert_nil @open_advisory_only.workspace_repository

      # Create an open advisory with a workspace
      @open_advisory = create(:repository_advisory, :with_workspace, repository: @repository)
      @open_workspace = @open_advisory.workspace_repository
      refute_nil @open_workspace

      # Create a published advisory where the workspace has been deleted
      @published_advisory_only = create(:published_repository_advisory, :with_workspace, repository: @repository)
      old_workspace_repository = @published_advisory_only.workspace_repository
      @published_advisory_only.workspace_repository.remove(@admin, synchronous: true)
      old_workspace_repository.reload
      assert old_workspace_repository.deleted?    # Workspace is deleted...
      assert_nil @published_advisory_only.workspace_repository_id # and the id is cleared

      # Create a published advisory with a workspace
      # Note: We should always clean up workspaces when an advisory is published,
      #       but we should attempt to remove permissions in the event cleanup fails
      @published_advisory = create(:published_repository_advisory, :with_workspace, repository: @repository)
      @published_workspace = @published_advisory.workspace_repository
      refute_nil @published_workspace

      # Create a closed advisory without a workspace
      @closed_advisory_only = create(:closed_repository_advisory, repository: @repository)
      assert_nil @closed_advisory_only.workspace_repository

      # Create a closed advisory with a workspace
      @closed_advisory = create(:closed_repository_advisory, :with_workspace, repository: @repository)
      @closed_workspace = @closed_advisory.workspace_repository
      refute_nil @closed_workspace

      # Create an open advisory with a workspace that has explicit collaborators
      @open_explicit_collab_advisory = create(:repository_advisory, :with_workspace, repository: @public_repo)
      @open_explicit_collab_advisory.add_collaborator(@collab)
      @open_explicit_collab_advisory.add_collaborator(@collab_team)
      @open_explicit_collab_workspace = @open_explicit_collab_advisory.workspace_repository
      refute_nil @open_explicit_collab_workspace
      invitation = RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_explicit_collab_workspace.id)
      assert invitation
      invitation&.accept!(acceptor: @collab)

      # Create an open advisory with a workspace that has invited explicit collaborators
      @open_invited_explicit_collab_advisory = create(:repository_advisory, :with_workspace, repository: @public_repo)
      @open_invited_explicit_collab_advisory.add_collaborator(@collab)
      @open_invited_explicit_collab_workspace = @open_invited_explicit_collab_advisory.workspace_repository
      refute_nil @open_invited_explicit_collab_workspace
      invitation = RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_invited_explicit_collab_workspace.id)
      assert invitation
    end
  end

  context ".revoke" do
    test "passes on information about the actor" do
      @open_advisory_only.add_collaborator(@collab)
      @repository.add_member(@collab, action: :admin)
      Repository::AdvisoryAbilityManager.revoke(@collab, repository: @repository, actor: @collab)

      assert_equal "collaborator_removed", @open_advisory_only.events.last.event
      assert_equal @open_advisory_only.events.last.subject, @open_advisory_only.events.last.actor
    end

    test "collaborator_removed event uses the Advisory's author as the actor if the actor is not passed through" do
      @open_advisory_only.add_collaborator(@collab)
      @repository.add_member(@collab, action: :admin)
      Repository::AdvisoryAbilityManager.revoke(@collab, repository: @repository)

      assert_equal "collaborator_removed", @open_advisory_only.events.last.event
      assert_equal @open_advisory_only.author, @open_advisory_only.events.last.actor
    end
  end

  context "syncing users" do
    test "syncing an admin grant adds the user to undisclosed workspaces" do
      refute @open_workspace.adminable_by?(@rando)
      refute @closed_workspace.adminable_by?(@rando)
      refute @published_workspace.adminable_by?(@rando)

      Repository::AdvisoryAbilityManager.grant(@rando, repository: @repository, action: :admin)

      assert @open_workspace.adminable_by?(@rando)
      assert @closed_workspace.adminable_by?(@rando)
      assert @published_workspace.adminable_by?(@rando)
    end

    test "syncing a write grant removes the user from all workspaces where they aren't explicit collaborators" do
      assert @open_workspace.adminable_by?(@collab)
      assert @closed_workspace.adminable_by?(@collab)
      assert @published_workspace.adminable_by?(@collab)
      refute @open_explicit_collab_workspace.adminable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)

      Repository::AdvisoryAbilityManager.grant(@collab, repository: @repository, action: :write)
      Repository::AdvisoryAbilityManager.grant(@collab, repository: @public_repo, action: :write)

      refute @open_workspace.adminable_by?(@collab)
      refute @open_workspace.writable_by?(@collab)
      refute @closed_workspace.adminable_by?(@collab)
      refute @closed_workspace.writable_by?(@collab)
      refute @published_workspace.adminable_by?(@collab)
      refute @published_workspace.writable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)
      assert RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_invited_explicit_collab_workspace.id, permissions: :write)
    end

    test "syncing a read grant removes the user from all workspaces where they aren't explicit collaborators" do
      assert @open_workspace.adminable_by?(@collab)
      assert @closed_workspace.adminable_by?(@collab)
      assert @published_workspace.adminable_by?(@collab)
      refute @open_explicit_collab_workspace.adminable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)

      Repository::AdvisoryAbilityManager.grant(@collab, repository: @repository, action: :read)
      Repository::AdvisoryAbilityManager.grant(@collab, repository: @public_repo, action: :read)

      refute @open_workspace.adminable_by?(@collab)
      refute @open_workspace.readable_by?(@collab)
      refute @closed_workspace.adminable_by?(@collab)
      refute @closed_workspace.readable_by?(@collab)
      refute @published_workspace.adminable_by?(@collab)
      refute @published_workspace.readable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)
      assert RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_invited_explicit_collab_workspace.id, permissions: :write)
    end

    test "syncing a revoke grant removes the user from advisories & undisclosed workspaces" do
      assert @open_workspace.adminable_by?(@collab)
      assert @closed_workspace.adminable_by?(@collab)
      assert @published_workspace.adminable_by?(@collab)
      assert @open_explicit_collab_advisory.writable_by?(@collab)
      refute @open_explicit_collab_workspace.adminable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)

      Repository::AdvisoryAbilityManager.revoke(@collab, repository: @repository)
      Repository::AdvisoryAbilityManager.revoke(@collab, repository: @public_repo)

      refute @open_workspace.adminable_by?(@collab)
      refute @open_workspace.readable_by?(@collab)
      refute @closed_workspace.adminable_by?(@collab)
      refute @closed_workspace.readable_by?(@collab)
      refute @published_workspace.adminable_by?(@collab)
      refute @published_workspace.readable_by?(@collab)
      refute @open_explicit_collab_advisory.writable_by?(@collab)
      refute @open_explicit_collab_workspace.writable_by?(@collab)
      refute @open_explicit_collab_workspace.readable_by?(@collab)
      refute RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_invited_explicit_collab_workspace.id)
    end
  end

  context "syncing teams" do
    test "syncing an admin grant adds the team to undisclosed workspaces" do
      refute @open_workspace.adminable_by?(@other_team)
      refute @closed_workspace.adminable_by?(@other_team)
      refute @published_workspace.adminable_by?(@other_team)

      Repository::AdvisoryAbilityManager.grant(@other_team, repository: @repository, action: :admin)

      assert @open_workspace.adminable_by?(@other_team)
      assert @closed_workspace.adminable_by?(@other_team)
      assert @published_workspace.adminable_by?(@other_team)
    end

    test "syncing a write grant removes the team from all workspaces where they aren't explicit collaborators" do
      assert @open_workspace.adminable_by?(@collab_team)
      assert @closed_workspace.adminable_by?(@collab_team)
      assert @published_workspace.adminable_by?(@collab_team)
      refute @open_explicit_collab_workspace.adminable_by?(@collab_team)
      assert @open_explicit_collab_workspace.writable_by?(@collab_team)

      Repository::AdvisoryAbilityManager.grant(@collab_team, repository: @repository, action: :write)
      Repository::AdvisoryAbilityManager.grant(@collab_team, repository: @public_repo, action: :write)

      refute @open_workspace.adminable_by?(@collab_team)
      refute @open_workspace.writable_by?(@collab_team)
      refute @closed_workspace.adminable_by?(@collab_team)
      refute @closed_workspace.writable_by?(@collab_team)
      refute @published_workspace.adminable_by?(@collab_team)
      refute @published_workspace.writable_by?(@collab_team)
      assert @open_explicit_collab_workspace.writable_by?(@collab_team)
    end

    test "syncing a read grant removes the team from all workspaces where they aren't explicit collaborators" do
      assert @open_workspace.adminable_by?(@collab_team)
      assert @closed_workspace.adminable_by?(@collab_team)
      assert @published_workspace.adminable_by?(@collab_team)
      refute @open_explicit_collab_workspace.adminable_by?(@collab_team)
      assert @open_explicit_collab_workspace.writable_by?(@collab_team)

      Repository::AdvisoryAbilityManager.grant(@collab_team, repository: @repository, action: :read)
      Repository::AdvisoryAbilityManager.grant(@collab_team, repository: @public_repo, action: :read)

      refute @open_workspace.adminable_by?(@collab_team)
      refute @open_workspace.readable_by?(@collab_team)
      refute @closed_workspace.adminable_by?(@collab_team)
      refute @closed_workspace.readable_by?(@collab_team)
      refute @published_workspace.adminable_by?(@collab_team)
      refute @published_workspace.readable_by?(@collab_team)
      assert @open_explicit_collab_workspace.writable_by?(@collab_team)
    end

    test "syncing a revoke grant removes the team from advisories & undisclosed workspaces" do
      assert @open_workspace.adminable_by?(@collab_team)
      assert @closed_workspace.adminable_by?(@collab_team)
      assert @published_workspace.adminable_by?(@collab_team)
      assert @open_explicit_collab_advisory.writable_by?(@collab)
      refute @open_explicit_collab_workspace.adminable_by?(@collab_team)
      assert @open_explicit_collab_workspace.writable_by?(@collab_team)

      Repository::AdvisoryAbilityManager.revoke(@collab_team, repository: @repository)
      Repository::AdvisoryAbilityManager.revoke(@collab_team, repository: @public_repo)

      refute @open_workspace.adminable_by?(@collab_team)
      refute @open_workspace.readable_by?(@collab_team)
      refute @closed_workspace.adminable_by?(@collab_team)
      refute @closed_workspace.readable_by?(@collab_team)
      refute @published_workspace.adminable_by?(@collab_team)
      refute @published_workspace.readable_by?(@collab_team)
      refute @open_explicit_collab_advisory.writable_by?(@collab_team)
      refute @open_explicit_collab_workspace.writable_by?(@collab_team)
      refute @open_explicit_collab_workspace.readable_by?(@collab_team)
    end
  end

  context "changing visibility" do
    test "removes users from advisories & undisclosed workspaces when they can no longer access the repo" do
      @public_repo.add_member(@collab, action: :read)
      @open_explicit_collab_advisory.add_collaborator(@rando)
      invite = RepositoryInvitation.find_by(invitee_id: @rando.id, repository_id: @open_explicit_collab_workspace.id)
      invite&.accept!(acceptor: @rando)
      @open_invited_explicit_collab_advisory.add_collaborator(@rando)

      assert @open_explicit_collab_advisory.writable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)
      assert RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_invited_explicit_collab_workspace.id)
      assert @open_explicit_collab_advisory.writable_by?(@rando)
      assert @open_explicit_collab_workspace.writable_by?(@rando)
      assert RepositoryInvitation.find_by(invitee_id: @rando.id, repository_id: @open_invited_explicit_collab_workspace.id)

      @public_repo.update(public: false)
      Repository::AdvisoryAbilityManager.change_visibility(repository: @public_repo)

      assert @open_explicit_collab_advisory.writable_by?(@collab)
      assert @open_explicit_collab_workspace.writable_by?(@collab)
      assert RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @open_invited_explicit_collab_workspace.id)
      refute @open_explicit_collab_advisory.writable_by?(@rando)
      refute @open_explicit_collab_workspace.writable_by?(@rando)
      refute RepositoryInvitation.find_by(invitee_id: @rando.id, repository_id: @open_invited_explicit_collab_workspace.id)
    end
  end

  context "changing ownership of workspaces" do
    test "when the new owner is an organization" do
      assert @open_workspace.adminable_by?(@owner)
      assert @closed_workspace.adminable_by?(@owner)
      assert @published_workspace.adminable_by?(@owner)

      assert @open_workspace.adminable_by?(@collab_team)
      assert @closed_workspace.adminable_by?(@collab_team)
      assert @published_workspace.adminable_by?(@collab_team)

      assert @open_workspace.adminable_by?(@collab)
      assert @closed_workspace.adminable_by?(@collab)
      assert @published_workspace.adminable_by?(@collab)

      @new_owner = create(:paid_user, login: "new-owner")
      @new_org   = create(:organization, login: "new-corp", admin: @new_owner)
      only = [TransferWorkspaceJob, WorkspaceAbilitySetupJob]
      perform_enqueued_jobs(only: only) do
        @repository.transfer_ownership_to(@new_org, actor: @owner)
      end

      @open_workspace = @open_advisory.reload.workspace_repository
      @closed_workspace = @closed_advisory.reload.workspace_repository
      @published_workspace = @published_advisory.reload.workspace_repository

      assert_equal_owner @new_org, @repository.owner
      assert_equal @new_org, @open_workspace.owner
      assert_equal @new_org, @closed_workspace.owner
      assert_equal @new_org, @published_workspace.owner

      # New Org gains admin abilities
      assert @repository.adminable_by?(@new_owner)
      assert @open_workspace.adminable_by?(@new_owner)
      assert @closed_workspace.adminable_by?(@new_owner)
      assert @published_workspace.adminable_by?(@new_owner)

      # Collaborator retains abilities
      assert @open_workspace.adminable_by?(@collab)
      assert @closed_workspace.adminable_by?(@collab)
      assert @published_workspace.adminable_by?(@collab)

      # Old Org loses abilities
      refute @open_workspace.adminable_by?(@owner)
      refute @closed_workspace.adminable_by?(@owner)
      refute @published_workspace.adminable_by?(@owner)

      # Old Org teams lose abilities
      refute @open_workspace.adminable_by?(@collab_team)
      refute @closed_workspace.adminable_by?(@collab_team)
      refute @published_workspace.adminable_by?(@collab_team)
    end

    test "when the new owner is a user" do
      assert @open_workspace.adminable_by?(@owner)
      assert @closed_workspace.adminable_by?(@owner)
      assert @published_workspace.adminable_by?(@owner)

      assert @open_workspace.adminable_by?(@collab)
      assert @closed_workspace.adminable_by?(@collab)
      assert @published_workspace.adminable_by?(@collab)

      assert @open_workspace.adminable_by?(@collab_team)
      assert @closed_workspace.adminable_by?(@collab_team)
      assert @published_workspace.adminable_by?(@collab_team)

      @new_owner = create(:user, login: "new-user")
      only = [TransferWorkspaceJob]
      perform_enqueued_jobs(only: only) do
        @repository.transfer_ownership_to(@new_owner, actor: @owner)
      end

      @open_workspace = @open_advisory.reload.workspace_repository
      @closed_workspace = @closed_advisory.reload.workspace_repository
      @published_workspace = @published_advisory.reload.workspace_repository

      assert_equal_owner @new_owner, @repository.owner
      assert_equal @new_owner, @open_workspace.owner
      assert_equal @new_owner, @closed_workspace.owner
      assert_equal @new_owner, @published_workspace.owner

      # New User gains admin abilities
      assert @repository.adminable_by?(@new_owner)
      assert @open_workspace.adminable_by?(@new_owner)
      assert @closed_workspace.adminable_by?(@new_owner)
      assert @published_workspace.adminable_by?(@new_owner)

      # Collaborator loses admin abilities
      # - Personal Repos only support read/write collaborators
      refute @repository.adminable_by?(@collab)
      refute @open_workspace.adminable_by?(@collab)
      refute @closed_workspace.adminable_by?(@collab)
      refute @published_workspace.adminable_by?(@collab)

      # Old Org loses abilities
      refute @repository.adminable_by?(@owner)
      refute @open_workspace.adminable_by?(@owner)
      refute @closed_workspace.adminable_by?(@owner)
      refute @published_workspace.adminable_by?(@owner)

      # Old Org teams lose abilities
      refute @repository.adminable_by?(@collab_team)
      refute @open_workspace.adminable_by?(@collab_team)
      refute @closed_workspace.adminable_by?(@collab_team)
      refute @published_workspace.adminable_by?(@collab_team)
    end
  end

  context "cleaning up workspaces on repository deletion" do
    test "workspaces are deleted when their parent repository is deleted" do
      repository = create(:private_repository, owner: @org)
      advisories = create_list(:repository_advisory, 3, :with_workspace, repository: repository)

      advisories.each do |advisory|
        assert Repositories::Public.find_active(advisory.workspace_repository_id)
      end

      perform_enqueued_jobs(only: RepositoryOrchestrationJob) do
        repository.remove(@owner, synchronous: true)
      end

      advisories.each do |advisory|
        assert_nil Repositories::Public.find_active(advisory.workspace_repository_id)
      end
    end
  end

  context "remove_collaborators_from_organizations" do
    test "removes repo advisories collaborators from the orgs" do
      other_org = create(:organization, login: "other-org")
      other_repo = create(:repository, owner: other_org)
      other_user = create(:user)
      advisory = create(:repository_advisory, repository: @public_repo)
      other_advisory = create(:repository_advisory, repository: other_repo)

      @org.add_member(@rando)
      advisory.add_collaborator(@rando)

      other_org.add_member(other_user)
      other_advisory.add_collaborator(other_user)

      assert advisory.writable_by?(@rando)
      assert other_advisory.writable_by?(other_user)

      Repository::AdvisoryAbilityManager.remove_collaborators_from_organizations(collabs: [@rando, other_user], organizations: [@org, other_org])

      refute advisory.writable_by?(@rando)
      refute other_advisory.writable_by?(other_user)
    end

    test "removes repo advisory collaborators even if the user is not a collaborator of the repo" do
      advisory = create(:repository_advisory, repository: @public_repo)
      advisory.add_collaborator(@rando)
      @org.add_member(@rando)

      refute @public_repo.member?(@rando)

      assert advisory.writable_by?(@rando)
      assert advisory.readable_by?(@rando)

      Repository::AdvisoryAbilityManager.remove_collaborators_from_organizations(collabs: [@rando], organizations: [@org])

      refute advisory.writable_by?(@rando)
      refute advisory.readable_by?(@rando)
    end

    test "removes only the repo advisories collaborators from repos that belong to the organizations" do
      member1 = create(:user)
      member2 = create(:user)
      non_org_member = create(:user)
      org_advisory1 = create(:repository_advisory, repository: @public_repo)
      org_advisory2 = create(:repository_advisory, repository: @public_repo)
      no_org_advisory3  = create(:repository_advisory)
      @org.add_member(member1)
      @org.add_member(member2)
      org_advisory1.add_collaborator(member1)
      org_advisory2.add_collaborator(member2)
      org_advisory2.add_collaborator(non_org_member)
      no_org_advisory3.add_collaborator(member2)
      no_org_advisory3.add_collaborator(non_org_member)


      assert org_advisory1.writable_by?(member1)
      assert org_advisory2.writable_by?(member2)
      assert org_advisory2.writable_by?(non_org_member)
      assert no_org_advisory3.writable_by?(member2)
      assert no_org_advisory3.writable_by?(non_org_member)

      Repository::AdvisoryAbilityManager.remove_collaborators_from_organizations(collabs: [member1, member2, non_org_member], organizations: [@org])

      refute org_advisory1.writable_by?(member1)
      refute org_advisory2.writable_by?(member2)
      refute org_advisory2.writable_by?(non_org_member)
      assert no_org_advisory3.writable_by?(member2)
      assert no_org_advisory3.writable_by?(non_org_member)

    end

    test "removes the repo advisory and workspace collaborators" do
      collab = create(:user)
      advisory = create(:repository_advisory, :with_workspace, repository: @public_repo)
      workspace = advisory.workspace_repository
      advisory.add_collaborator(collab)
      @org.add_member(collab)
      repo_invitation = RepositoryInvitation.find_by(invitee_id: collab.id, repository_id: workspace.id)
      repo_invitation&.accept!(acceptor: collab)

      assert advisory.writable_by?(collab)
      refute_nil advisory.workspace_repository
      assert advisory.workspace_repository.writable_by?(collab)

      Repository::AdvisoryAbilityManager.remove_collaborators_from_organizations(collabs: [collab], organizations: [@org])

      refute advisory.writable_by?(collab)
      refute advisory.readable_by?(collab)
      refute workspace.writable_by?(collab)
    end
  end
end if GitHub.repository_advisories_enabled?
