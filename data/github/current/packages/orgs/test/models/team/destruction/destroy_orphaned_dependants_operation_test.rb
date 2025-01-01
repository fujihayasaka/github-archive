# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamDestructionDestroyOrphanedDependantsOperationTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org = create :organization, plan: "business", admin: @owner
    @org2 = create :organization, plan: "business", admin: @owner
  end

  setup do
    @team = create :team, organization: @org, privacy: :closed, ldap_mapping: LdapMapping.new(dn: "cn=enterprise,ou=groups,dc=github,dc=com")
    @team2 = create :team, organization: @org2, privacy: :closed, ldap_mapping: LdapMapping.new(dn: "cn=enterprise,ou=groups,dc=github,dc=com")
  end

  test "destroys membership requests only for a deleted team" do
    create(:team_membership_request, team: @team)
    create(:team_membership_request, team: @team2)

    assert_difference "TeamMembershipRequest.count", -1 do
      @team.delete
      perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
        DestroyOrphanedTeamDependenciesJob.perform_later
      end
    end
  end

  test "deletes user roles only for a deleted team" do
    org_repo = create :repository, owner: @org
    org_repo.send(:grant, @team, :triage)

    org_repo2 = create :repository, owner: @org2
    org_repo2.send(:grant, @team2, :triage)

    assert_difference("UserRole.count", -1) do
      @team.delete
      perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
        DestroyOrphanedTeamDependenciesJob.perform_later
      end
    end
  end

  context "Destroys team invitations" do
    test "leaves the associated organization invitations only for a deleted team" do
      create(:team_invitation, team: @team, organization_invitation: create(:organization_invitation, organization: @org))
      create(:team_invitation, team: @team2, organization_invitation: create(:organization_invitation, organization: @org2))

      assert_difference("TeamInvitation.count", -1) do
        assert_difference("OrganizationInvitation.count", 0) do
          @team.delete
          perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
            DestroyOrphanedTeamDependenciesJob.perform_later
          end
        end
      end
    end

    test "does not delete records that are associated with organization invitations that have been accepted" do
      org_invitation = create(:organization_invitation, organization: @org)
      create(:team_invitation, team: @team, organization_invitation: org_invitation)
      org_invitation.accept

      assert_difference("TeamInvitation.count", 0) do
        assert_difference("OrganizationInvitation.count", 0) do
          @team.delete
          perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
            DestroyOrphanedTeamDependenciesJob.perform_later
          end
        end
      end
    end

    test "does not delete records that are associated with organization invitations that have been cancelled" do
      org_invitation = create(:organization_invitation, organization: @org)
      create(:team_invitation, team: @team, organization_invitation: org_invitation)
      org_invitation.cancel(actor: @owner)

      assert_difference("TeamInvitation.count", 0) do
        assert_difference("OrganizationInvitation.count", 0) do
          @team.delete
          perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
            DestroyOrphanedTeamDependenciesJob.perform_later
          end
        end
      end
    end
  end

  context "team change parent requests" do
    test "destroys child requests only for a deleted team" do
      child_team = create(:team, organization: @org, privacy: :closed)
      create(:team_change_parent_request,
        child_team: child_team,
        parent_team: @team,
        requester: @owner
      )

      child_team2 = create(:team, organization: @org2, privacy: :closed)
      create(:team_change_parent_request,
        child_team: child_team2,
        parent_team: @team2,
        requester: @owner
      )

      assert_difference("TeamChangeParentRequest.count", -1) do
        @team.delete
        perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
          DestroyOrphanedTeamDependenciesJob.perform_later
        end
      end
    end

    test "destroys parent requests only for a deleted team" do
      child_team = create(:team, organization: @org, privacy: :closed)
      create(:team_change_parent_request,
        child_team: child_team,
        parent_team: @team,
        requester: @owner
      )

      child_team2 = create(:team, organization: @org2, privacy: :closed)
      create(:team_change_parent_request,
        child_team: child_team2,
        parent_team: @team2,
        requester: @owner
      )

      assert_difference("TeamChangeParentRequest.count", -1) do
        @team.delete
        perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
          DestroyOrphanedTeamDependenciesJob.perform_later
        end
      end
    end
  end

  test "destroys ldap mappings only for a deleted team" do
    if GitHub.enterprise?
      assert_difference("LdapMapping.count", -1) do
        @team.delete
        perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
          DestroyOrphanedTeamDependenciesJob.perform_later
        end
      end
    end
  end

  test "destroys team group mappings only for a deleted team" do
    create(:team_group_mapping, team: @team)
    create(:team_group_mapping, team: @team2)

    assert_difference("Team::GroupMapping.count", -1) do
      @team.delete
      perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
        DestroyOrphanedTeamDependenciesJob.perform_later
      end
    end
  end

  test "destroys the team's discussion posts only for a deleted team" do
    create(:discussion_post, team: @team)
    create(:discussion_post, team: @team2)

    assert_difference("DiscussionPost.count", -1) do
      @team.delete
      perform_enqueued_jobs only: [DestroyOrphanedTeamDependenciesJob] do
        DestroyOrphanedTeamDependenciesJob.perform_later
      end
    end
  end
end
