# typed: true
# frozen_string_literal: true

require "test_helper"

class ProjectAbilityDependencyTest < GitHub::TestCase
  fixtures do
    @owner = create(:user, login: "org-owner")
    @org = create(:organization, admin: @owner)
    @team = create(:team, organization: @org, privacy: :closed)
    @member = create(:user, login: "org-member")
    @org.add_member(@member)
    @unaffiliated_user = create(:user, login: "unaffiliated")

    @project = create(:project, owner: @org)
    @user_owned_project = create(:project, owner: @unaffiliated_user)
  end

  context "access levels" do
    test "granting read access doesn't grant any other access" do
      @project.update_org_permission(:read)
      assert @project.readable_by?(@member)
      refute @project.writable_by?(@member)
      refute @project.adminable_by?(@member)
    end

    test "granting write access also grants read access" do
      @project.update_org_permission(:write)
      assert @project.readable_by?(@member)
      assert @project.writable_by?(@member)
      refute @project.adminable_by?(@member)
    end

    test "granting admin access also grants read and write access" do
      @project.update_org_permission(:admin)
      assert @project.readable_by?(@member)
      assert @project.writable_by?(@member)
      assert @project.adminable_by?(@member)
    end
  end

  context "when a project is" do
    context "private" do
      test "only org owners can read it" do
        @project.update_org_permission(nil)
        @project.update_attribute(:public, false)

        assert @project.readable_by?(@owner)
        refute @project.readable_by?(@member)
      end
    end

    context "public" do
      test "anyone can read it" do
        @project.update_org_permission(nil)
        @project.update_attribute(:public, true)

        assert @project.readable_by?(nil)
      end

      test "only org owners can write to it" do
        @project.update_org_permission(nil)
        @project.update_attribute(:public, true)

        assert @project.writable_by?(@owner)
        refute @project.writable_by?(@member)
      end
    end
  end

  context "when an organization" do
    context "has not been granted anything on a project" do
      context "org owner" do
        test "can admin" do
          @project.update_org_permission(nil)
          assert @project.adminable_by?(@owner)
        end
      end

      context "org member" do
        test "cannot read" do
          @project.update_org_permission(nil)
          refute @project.readable_by?(@member)
        end
      end
    end

    context "has been granted read on a project" do
      context "org member" do
        test "can read" do
          @project.update_org_permission(:read)
          assert @project.readable_by?(@member)
        end

        test "cannot write" do
          @project.update_org_permission(:read)
          refute @project.writable_by?(@member)
        end
      end

      context "unaffiliated user" do
        test "cannot read" do
          @project.update_org_permission(:read)
          refute @project.readable_by?(@unaffiliated_user)
        end
      end
    end

    context "has been granted write on a project" do
      context "org member" do
        test "can write" do
          @project.update_org_permission(:write)
          assert @project.writable_by?(@member)
        end

        test "cannot admin" do
          @project.update_org_permission(:write)
          refute @project.adminable_by?(@member)
        end
      end

      context "unaffiliated user" do
        test "cannot read" do
          @project.update_org_permission(:write)
          refute @project.readable_by?(@unaffiliated_user)
        end
      end
    end

    context "has been granted admin on a project" do
      context "org member" do
        test "can admin" do
          @project.update_org_permission(:admin)
          assert @project.adminable_by?(@member)
        end
      end

      context "unaffiliated user" do
        test "cannot read" do
          @project.update_org_permission(:admin)
          refute @project.readable_by?(@unaffiliated_user)
        end
      end
    end

    context "has had its previous permission on a project revoked" do
      context "org owner" do
        test "can admin" do
          @project.update_org_permission(:admin)
          @project.update_org_permission(nil)

          assert @project.adminable_by?(@owner)
        end
      end

      context "org member" do
        test "cannot read" do
          @project.update_org_permission(:admin)
          @project.update_org_permission(nil)

          refute @project.readable_by?(@member)
        end
      end
    end
  end

  context "when a team" do
    context "has not been granted anything on a project" do
      context "team member" do
        test "cannot read" do
          @project.update_org_permission(nil)

          @team.add_member(@member)

          refute @project.readable_by?(@member)
        end
      end
    end

    context "has been granted read on a project" do
      context "team member" do
        test "can read but not write" do
          @project.update_org_permission(nil)

          @team.add_member(@member)
          @team.add_project(@project, :read)

          assert @project.readable_by?(@member)
          refute @project.writable_by?(@member)
        end
      end

      context "member of org but not team" do
        test "cannot read" do
          @project.update_org_permission(nil)

          @team.add_project(@project, :read)

          refute @project.readable_by?(@member)
        end
      end
    end

    context "has been granted write on a project" do
      context "team member" do
        test "can write but not admin" do
          @project.update_org_permission(nil)

          @team.add_member(@member)
          @team.add_project(@project, :write)

          assert @project.writable_by?(@member)
          refute @project.adminable_by?(@member)
        end
      end
    end

    context "has been granted admin on a project" do
      context "team member" do
        test "can admin" do
          @project.update_org_permission(nil)

          @team.add_member(@member)
          @team.add_project(@project, :admin)

          assert @project.adminable_by?(@member)
        end
      end
    end
  end

  context "when a user" do
    test "has not been granted anything on a project, they cannot read" do
      @project.update_org_permission(nil)

      refute @project.readable_by?(@member)
    end

    test "has been granted read on a project, they can read but not write" do
      @project.update_org_permission(nil)
      @project.update_user_permission(@member, :read)

      assert @project.readable_by?(@member)
      refute @project.writable_by?(@member)
    end

    test "has been granted permission on a project, an audit log event is published" do
      events = subscribe "project.update_user_permission"

      @project.update_org_permission(nil)
      @project.update_user_permission(@member, :read)

      assert @project.readable_by?(@member)

      assert event = events.pop, "an event was expected"
      assert_equal "project.update_user_permission", event.name
      assert_equal :read, event.payload[:changes][:permission]
      assert_nil event.payload[:changes][:old_permission]
      assert_equal @project.name, event.payload[:project]
      assert_equal @project.id, event.payload[:project_id]
      assert_equal @member.login, event.payload[:user]
      assert_equal @member.id, event.payload[:user_id]
    end

    test "has been granted write on a project, they can write but not admin" do
      @project.update_org_permission(nil)
      @project.update_user_permission(@member, :write)

      assert @project.writable_by?(@member)
      refute @project.adminable_by?(@member)
    end

    test "has been granted admin on a project, they can admin" do
      @project.update_org_permission(nil)
      @project.update_user_permission(@member, :admin)

      assert @project.adminable_by?(@member)
    end

    test "has not been granted read access on a project, clearing permission is a noop" do
      events = subscribe "project.update_user_permission"
      refute @project.readable_by?(@unaffiliated_user)

      @project.update_user_permission(@unaffiliated_user, nil)

      assert_nil events.pop, "a project.update_user_permission event was not expected"
      refute @project.readable_by?(@unaffiliated_user)
    end
  end

  context "multiple permission sources" do
    context "from the org and a team" do
      test "if a team grants higher permissions than the org, the team's permission wins" do
        @project.update_org_permission(:read)

        @team.add_member(@member)
        @team.add_project(@project, :write)

        assert @project.writable_by?(@member)
      end

      test "if the org grants higher permissions than a team, the org's permission wins" do
        @project.update_org_permission(:write)

        @team.add_member(@member)
        @team.add_project(@project, :read)

        assert @project.writable_by?(@member)
      end
    end

    context "from nested teams" do
      test "if a parent team grants permissions and its nested team doesn't, the parent team's permission applies" do
        @project.update_org_permission(nil)

        @team.add_project(@project, :read)

        nested_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
        nested_team.add_member(@member)

        refute Ability.can?(nested_team, :read, @project) # nested_team does *not* grant permission on the project
        assert @project.readable_by?(@member) # @project is readable based on membership in @team
      end

      test "if a parent team grants lower permissions than its nested team and the user is a member of the nested team, the nested team's permission wins" do
        @project.update_org_permission(nil)

        @team.add_project(@project, :read)

        nested_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
        nested_team.add_member(@member)
        nested_team.add_project(@project, :write)

        assert @project.writable_by?(@member)
      end

      test "if a parent team grants lower permissions than its nested team and the user is only a member of the parent team, the parent team's permission wins" do
        @project.update_org_permission(nil)

        @team.add_project(@project, :read)
        @team.add_member(@member)

        nested_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @team.id)
        nested_team.add_project(@project, :write)

        assert @project.readable_by?(@member)
        refute @project.writable_by?(@member)
      end
    end

    context "from a team and an individual user permission" do
      test "if the user is granted higher permissions than a team, the user's permission wins" do
        @project.update_org_permission(nil)

        @team.add_member(@member)
        @team.add_project(@project, :read)

        @project.update_user_permission(@member, :write)

        assert @project.writable_by?(@member)
      end

      test "if a team is granted higher permissions than the user, the team's permission wins" do
        @project.update_org_permission(nil)

        @team.add_member(@member)
        @team.add_project(@project, :write)

        @project.update_user_permission(@member, :read)

        assert @project.writable_by?(@member)
      end
    end
  end

  context "on creation" do
    test "grants all org owners admin access" do
      org_owner = create(:user)
      org = create(:organization, admin: org_owner)

      project = create(:project, owner: org)

      assert project.adminable_by?(org_owner)
    end

    test "grants all org members write access" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)

      project = create(:project, owner: org)

      assert project.writable_by?(org_member)
      refute project.adminable_by?(org_member)
    end

    test "doesn't create any new abilities when a repo project is created" do
      repo = create(:repository, owner: @org)
      @team.add_repository(repo, :admin)

      assert_no_difference -> { Ability.count } do
        project = create(:project, owner: repo)
      end
    end
  end

  context "on deletion" do
    test "deletes all associated abilities" do
      @project.update_org_permission(:read)
      @project.update_user_permission(@member, :read)
      @team.add_project(@project, :read)

      # This should destroy 3 abilities on the project:
      # - The org's direct ability
      # - The member's direct ability
      # - The team's direct ability
      number_of_abilities = 3
      assert_difference(-> { Ability.where(subject_id: @project, subject_type: @project.class.to_s).count }, -number_of_abilities) do
        perform_enqueued_jobs(only: [ClearAbilitiesJob]) { @project.destroy }
      end
    end
  end

  context "on archival and restoration" do
    test "restores org owner permissions" do
      non_creator_org_owner = create(:user, login: "non-creator-org-owner")
      @org.add_admin(non_creator_org_owner)
      assert @project.adminable_by?(non_creator_org_owner)

      archived_record = Archived::Project.archive(@project)
      restored_record = archived_record.restore

      assert restored_record.adminable_by?(non_creator_org_owner)
    end

    test "does not restore the organization permission" do
      @project.update_org_permission(:read)

      member_with_read_via_org_permission = create(:user, login: "member-with-read-via-org-permission")
      @org.add_member(member_with_read_via_org_permission)
      assert @project.readable_by?(member_with_read_via_org_permission)

      only = [ClearAbilitiesJob]
      archived_record = perform_enqueued_jobs(only: only) { Archived::Project.archive(@project) }
      restored_record = archived_record.restore

      refute restored_record.readable_by?(member_with_read_via_org_permission)
    end

    test "does not restore team permissions" do
      @team.add_project(@project, :write)

      member_with_write_via_team_permission = create(:user, login: "member-with-write-via-team-permission")
      @org.add_member(member_with_write_via_team_permission)
      @team.add_member(member_with_write_via_team_permission)
      assert @project.writable_by?(member_with_write_via_team_permission)

      only = [ClearAbilitiesJob]
      archived_record = perform_enqueued_jobs(only: only) { Archived::Project.archive(@project) }
      restored_record = Archived::Project.find(@project.id).restore

      refute restored_record.writable_by?(member_with_write_via_team_permission)
    end

    test "does not restore direct collaborator permissions" do
      direct_collaborator_member = create(:user, login: "direct-collaborator-member")
      @org.add_member(direct_collaborator_member)
      @project.update_user_permission(direct_collaborator_member, :read)
      assert @project.readable_by?(direct_collaborator_member)

      only = [ClearAbilitiesJob]
      archived_record = perform_enqueued_jobs(only: only) { Archived::Project.archive(@project) }
      restored_record = Archived::Project.find(@project.id).restore

      refute restored_record.readable_by?(direct_collaborator_member)
    end
  end

  context "on reparenting from a repo to an org" do
    test "grants all org owners admin access" do
      org_owner = create(:user)
      org = create(:organization, admin: org_owner)
      repo = create(:repository, owner: org)
      project = create(:project, owner: repo)

      staff = create(:staff_admin_user)
      GitHub.context.push(actor_id: staff.id)

      project.change_owner!(new_owner: org)

      assert project.adminable_by?(org_owner)
    end

    test "grants all org members write access" do
      org = create(:organization)
      org_member = create(:user)
      org.add_member(org_member)

      repo = create(:repository, owner: org)
      project = create(:project, owner: repo)

      staff = create(:staff_admin_user)
      GitHub.context.push(actor_id: staff.id)

      project.change_owner!(new_owner: org)

      assert project.writable_by?(org_member)
      refute project.adminable_by?(org_member)
    end

    test "grants creator admin access if they're an org member" do
      org = create(:organization)
      creator = create(:user)
      org.add_member(creator)

      repo = create(:repository, owner: org)
      project = create(:project, owner: repo, creator: creator)

      staff = create(:staff_admin_user)
      GitHub.context.push(actor_id: staff.id)

      project.change_owner!(new_owner: org)

      assert project.adminable_by?(creator)
    end

    test "doesn't grant creator access if they're no longer an org member" do
      org = create(:organization)
      creator = create(:user)
      org.add_member(creator)

      repo = create(:repository, owner: org)
      project = create(:project, owner: repo, creator: creator)

      staff = create(:staff_admin_user)
      GitHub.context.push(actor_id: staff.id)

      perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
        org.remove_member(creator)
        project.change_owner!(new_owner: org)
      end

      refute project.readable_by?(creator)
    end
  end

  context "on reparenting from an org to a repo" do
    test "keeps all org owners admin access" do
      org_owner = create(:user)
      org = create(:organization, admin: org_owner)
      project = create(:project, owner: org)

      repo = create(:repository, owner: org)

      staff = create(:staff_admin_user)
      GitHub.context.push(actor_id: staff.id)

      project.change_owner!(new_owner: repo)

      assert project.adminable_by?(org_owner)
    end

    test "removes all abilities on the project" do
      org = create(:organization)
      project = create(:project, owner: org)

      org_member = create(:user)
      org.add_member(org_member)

      team_member = create(:user)
      team = create(:team, organization: org)
      org.add_member(team_member)
      team.add_member(team_member)
      team.add_project(project, :read)

      outside_collaborator = create(:user)
      project.update_user_permission(outside_collaborator, :read)

      repo = create(:repository, owner: org)

      staff = create(:staff_admin_user)
      GitHub.context.push(actor_id: staff.id)

      perform_enqueued_jobs(only: [ClearAbilitiesJob]) { project.change_owner!(new_owner: repo) }

      assert_empty Ability.where(subject_id: project.id, subject_type: "Project", priority: [Ability.priorities[:direct], Ability.priorities[:indirect]])
      assert_empty Authorization.service.actor_ids(actor_type: User, subject: project, through: [Team, Organization])
    end
  end

  context "when an existing organization member is upgraded to an owner" do
    test "they are granted admin access to the project" do
      refute @project.adminable_by?(@member)

      @org.update_member(@member, action: :admin)

      assert @project.adminable_by?(@member)
    end
  end

  context "when an existing organization owner is downgraded to a regular member" do
    test "their admin access on the project is removed" do
      tmp_org_owner = create(:user, login: "tmp-org-owner")
      @org.add_admin(tmp_org_owner)

      project = create(:project, owner: @org)
      project.update_org_permission(nil)

      assert project.adminable_by?(tmp_org_owner)

      @org.update_member(tmp_org_owner, action: :read)

      refute project.adminable_by?(tmp_org_owner)
    end
  end

  context "update_team_permission" do
    test "raises an error if a non-team is passed" do
      assert_raises(ArgumentError) do
        @project.update_team_permission(@member, :read)
      end
    end
  end

  context "update_user_permission" do
    test "works when the passed user is not a member of the project's owning organization" do
      @project.update_org_permission(nil)

      outside_collaborator = create(:user, login: "outside-collaborator")
      refute @project.readable_by?(outside_collaborator)

      @project.update_user_permission(outside_collaborator, :read)

      assert @project.readable_by?(outside_collaborator)
    end

    test "raises an error if a non-user is passed" do
      assert_raises(ArgumentError) do
        @project.update_user_permission(@team, :read)
      end
    end
  end

  context "users_with_access" do
    test "includes all org members when there's an org permission" do
      @project.update_org_permission(:read)
      assert_same_elements [@owner, @member], @project.users_with_access
    end

    test "excludes org members with no other permission sources when there's no org permission" do
      @project.update_org_permission(nil)
      assert_same_elements [@owner], @project.users_with_access
    end

    test "includes users with access from teams" do
      @project.update_org_permission(nil)

      team = create(:team, organization: @org)
      team_member = create(:user, login: "team-member")
      @org.add_member(team_member)
      team.add_member(team_member)
      team.add_project(@project, :read)

      assert_includes @project.users_with_access, team_member
    end

    test "includes users with direct access" do
      @project.update_org_permission(nil)

      outside_collaborator = create(:user, login: "outside-collaborator")
      @project.update_user_permission(outside_collaborator, :read)

      assert_includes @project.users_with_access, outside_collaborator
    end

    test "includes users up to an access level when passed a permission" do
      @project.update_org_permission(nil)

      read_team = create(:team, organization: @org)
      reader = create(:user, login: "reader")
      read_team.add_member(reader)
      read_team.add_project(@project, :read)

      write_team = create(:team, organization: @org)
      writer = create(:user, login: "writer")
      write_team.add_member(writer)
      write_team.add_project(@project, :write)

      assert_includes @project.users_with_access(permission: :any), @owner
      assert_includes @project.users_with_access(permission: :any), writer
      assert_includes @project.users_with_access(permission: :any), reader

      assert_includes @project.users_with_access(permission: :admin), @owner
      refute_includes @project.users_with_access(permission: :admin), writer
      refute_includes @project.users_with_access(permission: :admin), reader

      assert_includes @project.users_with_access(permission: :write), @owner
      assert_includes @project.users_with_access(permission: :write), writer
      refute_includes @project.users_with_access(permission: :write), reader

      assert_includes @project.users_with_access(permission: :read), @owner
      refute_includes @project.users_with_access(permission: :read), writer
      assert_includes @project.users_with_access(permission: :read), reader
    end
  end

  context "direct_teams" do
    test "returns nothing for a repository-owned project" do
      repo = create(:repository)
      repo_project = create(:project, owner: repo)

      assert_empty repo_project.direct_teams
    end

    test "will never return teams from an org other than this project's owner" do
      # We have safeguards throughout the application to prevent a team from
      # being added to a project that's owned by a different organization, so
      # we have to force it here by manually creating the Ability in order to
      # simulate the bad-data situation that would cause it.
      different_org = create(:organization, login: "different-org")
      different_org_team = create(:team, name: "different-org-team")

      same_org_ability = Ability.create!(
        actor_id: @team.id,
        actor_type: "Team",
        subject_id: @project.id,
        subject_type: "Project",
        action: :read,
        priority: :direct,
      )

      different_org_ability = Ability.create!(
        actor_id: different_org_team.id,
        actor_type: "Team",
        subject_id: @project.id,
        subject_type: "Project",
        action: :read,
        priority: :direct,
      )

      assert_predicate same_org_ability, :persisted?
      assert_predicate different_org_ability, :persisted?
      assert_same_elements [@team], @project.direct_teams
    end
  end

  context "visible_teams_for" do
    test "excludes teams that are not on the project" do
      no_project_team = create(:team, organization: @org, name: "no-project-team")
      project_team = create(:team, organization: @org, name: "project-team")
      project_team.add_project(@project, :read)

      assert_same_elements [project_team], @project.visible_teams_for(@owner)
    end

    test "excludes teams that are not visible to an org member" do
      closed_team = create(:team, organization: @org, name: "closed-team", privacy: :closed)
      hidden_secret_team = create(:team, organization: @org, name: "hidden-secret-team", privacy: :secret)
      visible_secret_team = create(:team, organization: @org, name: "visible-secret-team", privacy: :secret)
      visible_secret_team.add_member(@member)

      [closed_team, visible_secret_team, hidden_secret_team].each do |team|
        team.add_project(@project, :read)
      end

      assert_same_elements [closed_team, visible_secret_team], @project.visible_teams_for(@member)
    end

    test "excludes all teams for an outside collaborator" do
      outside_collab = create(:user, login: "outside-collab")
      @project.update_user_permission(outside_collab, :read)

      team = create(:team, organization: @org, name: "closed-team", privacy: :closed)
      team.add_project(@project, :read)

      assert_empty @project.visible_teams_for(outside_collab)
    end

    test "excludes all teams for a logged-out user" do
      team = create(:team, organization: @org, name: "closed-team", privacy: :closed)
      team.add_project(@project, :read)

      assert_empty @project.visible_teams_for(nil)
    end
  end

  context "addable_teams_for" do
    test "includes all visible teams for an org member with admin on the project" do
      @project.update_org_permission(nil)
      @project.update_user_permission(@member, :admin)

      @team.add_member(@member)
      secret_team_without_membership = create(:team, organization: @org, name: "secret-without-membership", privacy: :secret)
      closed_team_without_membership = create(:team, organization: @org, name: "without-membership", privacy: :closed)

      assert_same_elements [@team, closed_team_without_membership], @project.addable_teams_for(@member)
    end

    test "empty for an outside collaborator with admin on the project" do
      @project.update_org_permission(nil)

      outside_collaborator = create(:user, login: "outside-collaborator")
      @project.update_user_permission(outside_collaborator, :admin)

      assert_empty @project.addable_teams_for(outside_collaborator)
    end

    test "empty for an org member that only has write on the project" do
      @project.update_org_permission(nil)
      @project.update_user_permission(@member, :write)

      assert_empty @project.addable_teams_for(@member)
    end

    test "supports filtering by team name and slug" do
      owner = create(:user, login: "other-org-owner")
      org = create :organization, admin: owner
      project = create :project, owner: org
      team1 = create(:team, organization: org, name: "foo d")
      team2 = create(:team, organization: org, name: "bar")
      team3 = create(:team, organization: org, name: "far")

      assert_same_elements [team1], project.addable_teams_for(owner, query: "foo")
      assert_same_elements [team1], project.addable_teams_for(owner, query: "o-d")
      assert_same_elements [team1, team3], project.addable_teams_for(owner, query: "f")
      assert_same_elements [team2, team3], project.addable_teams_for(owner, query: "ar")
    end
  end

  context "for repo projects" do
    test "writable_by? is true for repo pushers" do
      pusher = create(:user)
      puller = create(:user)
      repo = create(:repository, owner: @org)
      repo.add_member(pusher, action: :write)
      repo.add_member(puller, action: :read)

      project = create(:project, owner: repo)
      assert project.writable_by?(pusher)
      refute project.writable_by?(puller)
    end

    test "readable_by? is true for repo pullers" do
      pusher = create(:user)
      puller = create(:user)
      repo = create(:private_repository, owner: @org)
      repo.add_member(pusher, action: :write)
      repo.add_member(puller, action: :read)

      project = create(:project, owner: repo)
      assert project.readable_by?(pusher)
      assert project.readable_by?(puller)
    end

    test "readable_by? is true for non-collabs on public repos" do
      repo = create(:public_repository, owner: @org)
      project = create(:project, owner: repo)
      assert project.readable_by?(create(:user))
      assert project.readable_by?(nil)
    end

    context "#async_viewer_can_update?" do
      test "returns true for users with push access to the repo" do
        pusher = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(pusher, action: :write)
        project = create(:project, owner: repo)

        assert project.async_viewer_can_update?(pusher).sync
      end

      test "returns false for users with read access to the repo" do
        puller = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(puller, action: :read)
        project = create(:project, owner: repo)

        refute project.async_viewer_can_update?(puller).sync
      end
    end

    context "#async_closable_by?" do
      test "returns true for users with push access to the repo" do
        pusher = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(pusher, action: :write)
        project = create(:project, owner: repo)

        assert project.async_closable_by?(pusher).sync
      end

      test "returns false for users with read access to the repo" do
        puller = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(puller, action: :read)
        project = create(:project, owner: repo)

        refute project.async_closable_by?(puller).sync
      end
    end

    context "#async_reopenable_by?" do
      test "returns true for users with push access to the repo" do
        pusher = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(pusher, action: :write)
        project = create(:project, owner: repo)

        assert project.async_reopenable_by?(pusher).sync
      end

      test "returns false for users with read access to the repo" do
        puller = create(:user)
        repo = create(:repository, owner: @org)
        repo.add_member(puller, action: :read)
        project = create(:project, owner: repo)

        refute project.async_reopenable_by?(puller).sync
      end
    end
  end

  if GitHub.email_verification_enabled?
    context "email verification" do
      test "validates that the user must have a verified email to create a project" do
        GitHub.context.push(actor_id: @owner.id)

        User.any_instance.stubs(:content_creation_requires_email_verification?).returns(true)
        project = build(:project, creator: @owner, owner: @org)

        assert_predicate @owner, :must_verify_email?,
          "Bad assumption: User is not required to verify their email address."
        refute_predicate project, :valid?
        assert_includes_match(/email address must be verified/, project.errors.full_messages)
      end

      test "validates that the user must have a verified email to create a column" do
        GitHub.context.push(actor_id: @owner.id)

        User.any_instance.stubs(:content_creation_requires_email_verification?).returns(true)
        column = build :project_column, project: @project

        assert_predicate @owner, :must_verify_email?,
          "Bad assumption: User is not required to verify their email address."
        refute_predicate column, :valid?
        assert_includes_match(/email address must be verified/, column.errors.full_messages)
      end

      test "validates that the user must have a verified email to create a card" do
        GitHub.context.push(actor_id: @owner.id)

        project_column = create(:project_column, project: @project)
        User.any_instance.stubs(:content_creation_requires_email_verification?).returns(true)
        card = build :note_project_card, column: project_column

        assert_predicate @owner, :must_verify_email?,
          "Bad assumption: User is not required to verify their email address."
        refute_predicate card, :valid?
        assert_includes_match(/email address must be verified/, card.errors.full_messages)
      end

      context "a verified user" do
        test "can create a project" do
          User.any_instance.stubs(:content_creation_requires_email_verification?).returns(true)
          create(:user_email, :verified, user: @owner)

          project = build(:project, creator: @owner, owner: @org)

          refute_predicate @owner, :must_verify_email?
          assert_predicate project, :valid?
        end

        test "can create a column" do
          User.any_instance.stubs(:content_creation_requires_email_verification?).returns(true)
          create(:user_email, :verified, user: @owner)
          column = build :project_column # creator will come from the context

          refute_predicate @owner, :must_verify_email?
          assert_predicate column, :valid?
        end

        test "can create a card" do
          project_column = create(:project_column, project: @project)
          User.any_instance.stubs(:content_creation_requires_email_verification?).returns(true)
          create(:user_email, :verified, user: @owner)
          card = build :note_project_card, column: project_column # creator will come from the context

          refute_predicate @owner, :must_verify_email?
          assert_predicate card, :valid?
        end
      end
    end
  end

  context "#viewer_can_change_visibility?" do
    test "returns true for an org admin even when org denies that privilege to members" do
      assert @project.adminable_by?(@owner)
      refute_predicate @org, :members_can_change_project_visibility?
      assert @project.viewer_can_change_visibility?(@owner)
    end

    test "returns true for a project admin when the org grants the necessary privilege to members" do
      @org.allow_members_to_change_project_visibility(actor: @owner)
      @project.update_user_permission(@member, :admin)

      assert @project.adminable_by?(@member)
      assert_predicate @org, :members_can_change_project_visibility?
      assert @project.viewer_can_change_visibility?(@member)
    end

    test "returns false for a project admin when the org does not grant the necessary privilege to members" do
      @project.update_user_permission(@member, :admin)

      assert @project.adminable_by?(@member)
      refute_predicate @org, :members_can_change_project_visibility?
      refute @project.viewer_can_change_visibility?(@member)
    end

    test "returns false for an org member who is not a project admin" do
      @org.allow_members_to_change_project_visibility(actor: @owner)

      refute @project.adminable_by?(@member)
      assert_predicate @org, :members_can_change_project_visibility?
      refute @project.viewer_can_change_visibility?(@member)
    end

    test "returns false for a project admin who is not an org member" do
      @org.allow_members_to_change_project_visibility(actor: @owner)
      @project.update_user_permission(@unaffiliated_user, :admin)

      refute @org.member?(@unaffiliated_user)
      assert @project.adminable_by?(@unaffiliated_user)
      assert_predicate @org, :members_can_change_project_visibility?
      refute @project.viewer_can_change_visibility?(@member)
    end

    test "returns true for an org member with greater privileges than org-wide writer default" do
      @org.allow_members_to_change_project_visibility(actor: @owner)
      @project.update_org_permission(:write)
      @project.update_user_permission(@member, :admin)

      assert @project.adminable_by?(@member)
      assert_predicate @org, :members_can_change_project_visibility?
      assert @project.viewer_can_change_visibility?(@member)
    end

    test "returns true for the owner of a user-owned project" do
      assert @user_owned_project.adminable_by?(@unaffiliated_user)
      assert @user_owned_project.viewer_can_change_visibility?(@unaffiliated_user)
    end

    test "returns true for a non-owner project admin of a user-owned project" do
      @user_owned_project.update_user_permission(@member, :admin)

      assert @user_owned_project.adminable_by?(@member)
      assert @user_owned_project.viewer_can_change_visibility?(@member)
    end

    test "returns false for a non-admin of a user-owned project" do
      refute @user_owned_project.adminable_by?(@member)
      refute @user_owned_project.viewer_can_change_visibility?(@member)
    end
  end

  context ".viewer_can_create_public_project?" do
    test "returns false for repository-owned projects" do
      refute Project.viewer_can_create_public_project?(viewer: @owner, project_owner: create(:repository, owner: @owner))
    end

    test "returns true for user-owned projects" do
      assert Project.viewer_can_create_public_project?(viewer: @unaffiliated_user, project_owner: @unaffiliated_user)
    end

    test "returns true for org-owned projects with no member restrictions" do
      @org.allow_members_to_change_project_visibility(actor: @owner)
      assert Project.viewer_can_create_public_project?(viewer: @member, project_owner: @org)
    end

    test "returns true for an admin of an org-owned projects in spite of member restrictions" do
      refute_predicate @org, :members_can_change_project_visibility?
      assert Project.viewer_can_create_public_project?(viewer: @owner, project_owner: @org)
    end
  end
end
