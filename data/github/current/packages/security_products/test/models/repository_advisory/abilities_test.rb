# typed: true
# frozen_string_literal: true

require "test_helper"

class RepositoryAdvisoryAbilitiesTest < GitHub::TestCase
  fixtures do
    @rando = create(:user, login: "rando")
    @collab = create(:user, login: "collab")
    @owner = create(:paid_user, login: "owner")

    @org   = create(:organization, login: "acme", admin: @owner)
    @admin = create(:user, login: "admin-user")
    @org.add_admin(@admin)

    @admin_team = create(:team, name: "admins",  organization: @org)
    @write_team = create(:team, name: "writers", organization: @org)
    @read_team  = create(:team, name: "readers", organization: @org)

    @repository = create(:private_repository, name: "acme", owner: @org)
    @repository.add_team(@admin_team, action: :admin)
    @repository.add_team(@write_team, action: :write)
    @repository.add_team(@read_team,  action: :read)

    @advisory = create(:repository_advisory, repository: @repository)
    # Make sure we run the ability setup background job
    perform_enqueued_jobs(only: [WorkspaceAbilitySetupJob]) do
      GitHub.context.push(actor_id: @owner.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@advisory, @owner).save!
    end
    refute_nil @advisory.workspace_repository

    # Setup a personal repo as well
    @personal_repository = create(:private_repository, name: "personal", owner: @owner)
    @personal_repository.add_member_without_validation_or_notifications(@collab, action: :write)

    @personal_advisory = create(:repository_advisory, repository: @personal_repository)
    # Make sure we run the ability setup background job
    perform_enqueued_jobs(only: [WorkspaceAbilitySetupJob]) do
      GitHub.context.push(actor_id: @owner.id)
      RepositoryAdvisory::WorkspaceRepositoryBuilder.perform(@personal_advisory, @owner).save!
    end
    refute_nil @personal_advisory.workspace_repository
  end

  test "random users have no access to any advisory by default" do
    refute @advisory.readable_by?(@rando)
    refute @advisory.workspace_repository.readable_by?(@rando)

    refute @personal_advisory.readable_by?(@rando)
    refute @personal_advisory.workspace_repository.readable_by?(@rando)
  end

  context "Personal Repositories" do
    test "owners have admin access to advisories by default" do
      assert @personal_repository.adminable_by?(@owner)
      assert @personal_advisory.adminable_by?(@owner)
      assert @personal_advisory.workspace_repository.adminable_by?(@owner)
    end

    test "collaborators have no access to advisories by default" do
      assert @personal_repository.writable_by?(@collab)
      refute @personal_advisory.readable_by?(@collab)
      refute @personal_advisory.workspace_repository.readable_by?(@collab)
    end

    test "a user with read access on the repository may be given write access to an advisory" do
      @personal_repository.add_member_without_validation_or_notifications(@rando, action: :read)

      assert @personal_repository.readable_by?(@rando)
      refute @personal_advisory.readable_by?(@rando)
      refute @personal_advisory.workspace_repository.readable_by?(@rando)

      @personal_advisory.add_collaborator(@rando)

      assert @personal_advisory.writable_by?(@rando)
      assert RepositoryInvitation.find_by(invitee_id: @rando.id, repository_id: @personal_advisory.workspace_repository.id)
    end

    test "a user without read access on the repository may not be given write access on an advisory" do
      refute @personal_repository.readable_by?(@rando)
      refute @personal_advisory.readable_by?(@rando)
      refute @personal_advisory.workspace_repository.readable_by?(@rando)

      @personal_advisory.add_collaborator(@rando)

      refute @personal_advisory.writable_by?(@rando)
      refute @personal_advisory.workspace_repository.writable_by?(@rando)
      refute RepositoryInvitation.find_by(invitee_id: @rando.id, repository_id: @personal_advisory.workspace_repository.id)
    end
  end

  context "Organization Owners" do
    test "advisory is adminable by default" do
      assert @repository.adminable_by?(@owner)
      assert @advisory.adminable_by?(@owner)
      assert @advisory.workspace_repository.adminable_by?(@owner)
    end
  end

  context "Organization Admins" do
    test "advisory is adminable by default" do
      assert @repository.adminable_by?(@admin)
      assert @advisory.adminable_by?(@admin)
      assert @advisory.workspace_repository.adminable_by?(@admin)
    end

    test "advisory is not adminable if the admin is removed from the org" do
      assert @repository.adminable_by?(@admin)
      assert @advisory.adminable_by?(@admin)
      assert @advisory.workspace_repository.adminable_by?(@admin)

      @org.remove_member!(@admin)

      refute @repository.adminable_by?(@admin)
      refute @advisory.adminable_by?(@admin)
      refute @advisory.workspace_repository.adminable_by?(@admin)
    end

    test "advisory is not adminable if the admin is reduced to an org member" do
      assert @repository.adminable_by?(@admin)
      assert @advisory.adminable_by?(@admin)
      assert @advisory.workspace_repository.adminable_by?(@admin)

      @org.update_member(@admin, action: :read)

      refute @repository.adminable_by?(@admin)
      refute @advisory.adminable_by?(@admin)
      refute @advisory.workspace_repository.adminable_by?(@admin)

      assert @repository.readable_by?(@admin)
      refute @advisory.readable_by?(@admin)
      refute @advisory.workspace_repository.readable_by?(@admin)
    end
  end

  context "Teams with admin abilities on the repository" do
    test "advisory is adminable by default" do
      assert @repository.adminable_by?(@admin_team)
      assert @advisory.adminable_by?(@admin_team)
      assert @advisory.workspace_repository.adminable_by?(@admin_team)
    end

    test "advisory is not adminable if the team is removed from the repo" do
      assert @repository.adminable_by?(@admin_team)
      assert @advisory.adminable_by?(@admin_team)
      assert @advisory.workspace_repository.adminable_by?(@admin_team)

      perform_enqueued_jobs(only: [DeleteDependentAbilitiesJob], queue: :delete_dependent_abilities) do
        @repository.remove_team(@admin_team)
      end

      refute @repository.adminable_by?(@admin_team)
      refute @advisory.adminable_by?(@admin_team)
      refute @advisory.workspace_repository.adminable_by?(@admin_team)
    end

    test "advisory is not adminable if the team loses admin abilities on the repo" do
      assert @repository.adminable_by?(@admin_team)
      assert @advisory.adminable_by?(@admin_team)
      assert @advisory.workspace_repository.adminable_by?(@admin_team)

      perform_enqueued_jobs(only: [DeleteDependentAbilitiesJob], queue: :delete_dependent_abilities) do
        @repository.add_team(@admin_team, action: :write)
      end

      refute @repository.adminable_by?(@admin_team)
      refute @advisory.adminable_by?(@admin_team)
      refute @advisory.workspace_repository.adminable_by?(@admin_team)

      assert @repository.writable_by?(@admin_team)
      refute @advisory.writable_by?(@admin_team)
      refute @advisory.workspace_repository.writable_by?(@admin_team)
    end
  end

  context "Members of teams with admin abilities on the repository" do
    test "advisory is adminable by default" do
      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)

      @admin_team.add_member(@collab)

      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)
    end

    test "advisory is not adminable if the member is removed from the team" do
      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)

      @admin_team.add_member(@collab)

      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      @admin_team.remove_member(@collab)

      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)
    end

    test "advisory is not adminable if the team is removed from the repo" do
      @admin_team.add_member(@collab)
      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      perform_enqueued_jobs(only: [DeleteDependentAbilitiesJob], queue: :delete_dependent_abilities) do
        @repository.remove_team(@admin_team)
      end

      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)
    end

    test "advisory is not adminable if the team loses admin abilities on the repo" do
      @admin_team.add_member(@collab)
      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      perform_enqueued_jobs(only: [DeleteDependentAbilitiesJob], queue: :delete_dependent_abilities) do
        @repository.add_team(@admin_team, action: :write)
      end

      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)

      assert @repository.writable_by?(@collab)
      refute @advisory.writable_by?(@collab)
      refute @advisory.workspace_repository.writable_by?(@collab)
    end
  end

  context "Teams with write abilities on the repository" do
    test "advisory is not writable by default" do
      assert @repository.writable_by?(@write_team)
      refute @advisory.writable_by?(@write_team)
      refute @advisory.workspace_repository.writable_by?(@write_team)
    end

    test "may be added as a collaborator on an advisory to gain write access" do
      @advisory.add_collaborator(@write_team)
      assert @advisory.writable_by?(@write_team)
      assert @advisory.workspace_repository.writable_by?(@write_team)
    end
  end

  context "Members of teams with write abilities on the repository" do
    test "advisory is not writable by default" do
      refute @repository.writable_by?(@collab)
      refute @advisory.writable_by?(@collab)
      refute @advisory.workspace_repository.writable_by?(@collab)

      @write_team.add_member(@collab)

      assert @repository.writable_by?(@collab)
      refute @advisory.writable_by?(@collab)
      refute @advisory.workspace_repository.writable_by?(@collab)
    end

    test "members have write access to advisories if their team is a collaborator on it" do
      @advisory.add_collaborator(@write_team)

      @write_team.add_member(@collab)

      assert @repository.writable_by?(@collab)
      assert @advisory.writable_by?(@collab)
      assert @advisory.workspace_repository.writable_by?(@collab)
    end
  end

  context "Teams with read abilities on the repository" do
    test "advisory is not readable by default" do
      assert @repository.readable_by?(@read_team)
      refute @advisory.readable_by?(@read_team)
      refute @advisory.workspace_repository.readable_by?(@read_team)
    end

    test "may be added as a collaborator on an advisory to gain read access" do
      @advisory.add_collaborator(@read_team)
      assert @advisory.readable_by?(@read_team)
      assert @advisory.workspace_repository.readable_by?(@read_team)
    end
  end

  context "Members of teams with read abilities on the repository" do
    test "advisory is not readable by default" do
      refute @repository.readable_by?(@collab)
      refute @advisory.readable_by?(@collab)
      refute @advisory.workspace_repository.readable_by?(@collab)

      @read_team.add_member(@collab)

      assert @repository.readable_by?(@collab)
      refute @advisory.readable_by?(@collab)
      refute @advisory.workspace_repository.readable_by?(@collab)
    end

    test "members have write access to advisories if their team is a collaborator on it" do
      @advisory.add_collaborator(@read_team)

      @read_team.add_member(@collab)

      assert @repository.readable_by?(@collab)
      assert @advisory.readable_by?(@collab)
      assert @advisory.workspace_repository.readable_by?(@collab)
    end
  end

  context "Collaborators with admin access to the repository" do
    test "advisory is adminable by default" do
      refute @repository.adminable_by?(@collab)

      @repository.add_member(@collab, action: :admin)

      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)
    end

    test "advisory is not adminable if the collaborator loses access to the repo" do
      refute @repository.adminable_by?(@collab)

      @repository.add_member(@collab, action: :admin)

      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      perform_enqueued_jobs(only: [DeleteDependentAbilitiesJob], queue: :delete_dependent_abilities) do
        @repository.remove_member(@collab)
      end

      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)
    end

    test "advisory is not adminable if the collaborator loses admin abilities on the repo" do
      refute @repository.adminable_by?(@collab)

      @repository.add_member(@collab, action: :admin)

      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      perform_enqueued_jobs(only: [DeleteDependentAbilitiesJob], queue: :delete_dependent_abilities) do
        @repository.update_member(@collab, action: :write)
      end

      refute @repository.adminable_by?(@collab)
      refute @advisory.adminable_by?(@collab)
      refute @advisory.workspace_repository.adminable_by?(@collab)

      assert @repository.writable_by?(@collab)
      refute @advisory.writable_by?(@collab)
      refute @advisory.workspace_repository.writable_by?(@collab)
    end
  end

  context "Collaborators with write access to the repository" do
    test "advisory is not writable by default" do
      refute @repository.writable_by?(@collab)
      @repository.add_member(@collab, action: :write)

      assert @repository.writable_by?(@collab)
      refute @advisory.writable_by?(@collab)
      refute @advisory.workspace_repository.writable_by?(@collab)
    end

    test "they can be granted write access to the repository and workspace" do
      refute @repository.writable_by?(@collab)

      @repository.add_member(@collab, action: :write)

      assert @repository.writable_by?(@collab)

      @advisory.add_collaborator(@collab)
      assert @advisory.writable_by?(@collab)
      assert RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @advisory.workspace_repository.id)
    end
  end

  context "Collaborators with read access to the repository" do
    test "advisory is not readable by default" do
      refute @repository.readable_by?(@collab)

      @repository.add_member(@collab, action: :read)

      assert @repository.readable_by?(@collab)
      refute @advisory.readable_by?(@collab)
      refute @advisory.workspace_repository.readable_by?(@collab)
    end

    test "they can be granted write access to the repository and workspace" do
      refute @repository.readable_by?(@collab)

      @repository.add_member(@collab, action: :write)

      assert @repository.readable_by?(@collab)

      @advisory.add_collaborator(@collab)
      assert @advisory.writable_by?(@collab)
      assert RepositoryInvitation.find_by(invitee_id: @collab.id, repository_id: @advisory.workspace_repository.id)
    end
  end

  context "Vulnerability reporters" do
    test "they are granted write access to the advisory and the vulnerability reporter repository role" do
      @repository.add_member(@collab, action: :read)

      advisory = create(:pending_pvd_repo_advisory, :with_workspace, repository: @repository, author: @collab)
      refute advisory.workspace_repository.member?(@collab)
      assert_equal "vulnerability_reporter", @collab.user_roles.where(target: advisory.workspace_repository).first.action_name
      assert advisory.workspace_repository.resources.contents.writable_by?(@collab)
    end
  end

  context "Transferring ownership of a repository" do
    test "advisory abilities are migrated correctly" do
      # The owner can admin everything
      assert @repository.adminable_by?(@owner)
      assert @advisory.adminable_by?(@owner)
      assert @advisory.workspace_repository.adminable_by?(@owner)

      # The admin team can admin everything
      assert @repository.adminable_by?(@admin_team)
      assert @advisory.adminable_by?(@admin_team)
      assert @advisory.workspace_repository.adminable_by?(@admin_team)

      # An admin collaborator can admin everything
      @repository.add_member(@collab, action: :admin)
      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      @new_owner = create(:paid_user, login: "new-owner")
      @new_org   = create(:organization, login: "new-corp", admin: @new_owner)
      @new_team  = create(:team, name: "new-team",  organization: @new_org)
      refute @repository.adminable_by?(@new_owner)
      refute @advisory.adminable_by?(@new_owner)
      refute @advisory.workspace_repository.adminable_by?(@new_owner)

      only = [TransferWorkspaceJob, WorkspaceAbilitySetupJob]
      perform_enqueued_jobs(only: only) do
        @repository.transfer_ownership_to(@new_org, actor: @owner, target_teams: [@new_team])
      end
      @advisory.reload

      assert_equal_owner @new_org, @repository.owner
      assert_equal_owner @new_org, @advisory.owner
      assert_equal @new_org, @advisory.workspace_repository.owner

      # The old owner loses admin abilities
      refute @repository.adminable_by?(@owner)
      refute @advisory.adminable_by?(@owner)
      refute @advisory.workspace_repository.adminable_by?(@owner)

      # The admin team loses admin abilities
      refute @repository.adminable_by?(@admin_team)
      refute @advisory.adminable_by?(@admin_team)
      refute @advisory.workspace_repository.adminable_by?(@admin_team)

      # The admin collaborator retains admin abilities
      assert @repository.adminable_by?(@collab)
      assert @advisory.adminable_by?(@collab)
      assert @advisory.workspace_repository.adminable_by?(@collab)

      # The new owner gains admin abilities
      assert @repository.adminable_by?(@new_owner)
      assert @advisory.adminable_by?(@new_owner)
      assert @advisory.workspace_repository.adminable_by?(@new_owner)

      # Teams nominated in the transfer do not gain admin abilities
      refute @repository.adminable_by?(@new_team)
      refute @advisory.adminable_by?(@new_team)
      refute @advisory.workspace_repository.adminable_by?(@new_team)
    end
  end
end if GitHub.repository_advisories_enabled?
