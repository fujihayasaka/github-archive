# typed: true
# frozen_string_literal: true

require "test_helpers/api_serializer_helper"

class OrgSerializersTest < Api::SerializerTestCase
  include PlatformTestHelpers::InterfaceHelpers

  fixtures do
    @admin = create(:user, login: "org-admin")
    @org   = create(:organization, admin: @admin)
    @team  = create(:team, organization: @org)

    @parent_team = create(:team, organization: @org, privacy: :closed)
    @child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: @parent_team.id)
    @parent_team.add_member(create(:user))
    @child_team.add_member(create(:user))
  end

  context "team_hash" do
    test "includes a privacy attr" do
      output = T.unsafe(self).team(@team)
      assert_equal "secret", output["privacy"]
    end

    test "includes notification setting attr if feature flag enabled" do
      output = T.unsafe(self).team(@team)
      assert_includes output, "notification_setting"
    end

    test "includes html_url" do
      org   = create(:organization, login: "apple")
      team  = create(:team, organization: org, name: "developers")

      output = T.unsafe(self).team(team)
      assert_equal "https://github.com/orgs/apple/teams/developers", output["html_url"]
    end

    context "with a :repo option" do
      test "returns repo-specific permissions" do
        repo = create(:repository, :minimal, owner: @org)
        admin_team = create(:team, organization: @org, permission: "pull")
        admin_team.add_repository(repo, :admin)

        output = T.unsafe(self).team(admin_team, repo: repo)
        assert_equal "admin", output["permission"]

        expected_permissions = {
          pull: true,
          triage: true,
          push: true,
          maintain: true,
          admin: true
        }.stringify_keys!

        assert_equal expected_permissions, output["permissions"]
      end

      test "returns fine grained repo-specific permissions for triage role" do
        org = create(:business_plus_organization)
        repo = create :private_repository, :minimal, owner: org

        triage_team = create(:team, organization: org)
        triage_team.add_repository(repo, :triage)

        output = T.unsafe(self).team(triage_team, repo: repo)

        expected_permissions = {
          pull: true,
          triage: true,
          push: false,
          maintain: false,
          admin: false
        }.stringify_keys!

        assert_equal expected_permissions, output["permissions"]
      end

    end

    context "without a :repo option" do
      test "returns team-specific permissions" do
        repo = create(:repository, :minimal, owner: @org)
        admin_team = create(:team, organization: @org, permission: "pull")
        admin_team.add_repository(repo, :admin)

        output = T.unsafe(self).team(admin_team)
        assert_equal "pull", output["permission"]
      end
    end

    context "parent team" do
      test "is parent team hash" do
        parent_team = create(:team, organization: @org, privacy: :closed)
        child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)
        parent = T.unsafe(self).team(parent_team)
        parent.delete("parent") # we only show one level of nested teams

        output = T.unsafe(self).team(child_team)

        assert_equal parent, output["parent"]
      end

      test "is nil when root team" do
        output = T.unsafe(self).team(@team)

        assert_nil output["parent"]
      end
    end

    test "includes created_at and updated_at fields when full hash is requested" do
      output = T.unsafe(self).team(@team, full: true)

      assert_equal @team.created_at, output["created_at"]
      assert_equal @team.updated_at, output["updated_at"]
    end

    test "excludes created_at and updated_at fields when full hash is requested" do
      output = T.unsafe(self).team(@team)

      refute output.key?("created_at"), "should not incude created_at key"
      refute output.key?("updated_at"), "should not include updated_at key"
    end

    context "members_count" do
      test "excluded when not full team_hash" do
        parent = T.unsafe(self).team(@parent_team)
        refute parent.key?("members_count"), "should not include members_count key"
      end

      test "included for full team_hash" do
        parent = T.unsafe(self).team(@parent_team, full: true)
        assert parent.key?("members_count"), "should include members_count key"
      end

      test "counts immediate members" do
        parent = T.unsafe(self).team(@parent_team, full: true)

        assert_equal @parent_team.members_scope(membership: :all).count, parent["members_count"]
      end

      test "counts immediate and child team members" do
        parent = T.unsafe(self).team(@parent_team, full: true)

        assert_equal @parent_team.members_scope.count, parent["members_count"]
      end
    end

    context "repos_count" do
      test "excluded when not full team_hash" do
        parent = T.unsafe(self).team(@parent_team)
        refute parent.key?("repos_count"), "should not include repos_count key"
      end

      test "included for full team_hash" do
        parent = T.unsafe(self).team(@parent_team, full: true)
        assert parent.key?("repos_count"), "should include repos_count key"
      end

      test "counts directly assigned repositories" do
        @parent_team.add_repository(create(:repository, :minimal, owner: @org), :admin)
        @child_team.add_repository(create(:repository, :minimal, owner: @org), :admin)

        child = T.unsafe(self).team(@child_team, full: true)

        assert_equal @child_team.repositories_scope(affiliation: :all).count, child["repos_count"]
      end

      test "counts direct and inherited repositories" do
        @parent_team.add_repository(create(:repository, :minimal, owner: @org), :admin)
        @child_team.add_repository(create(:repository, :minimal, owner: @org), :admin)

        child = T.unsafe(self).team(@child_team, full: true)

        assert_equal @child_team.repositories_scope(affiliation: :all).count, child["repos_count"]
      end
    end
  end

  TeamQuery = Api::App::PlatformClient.parse <<-'GRAPHQL'
    query($id: ID!, $includeFullTeamDetails: Boolean!) {
      node(id: $id) {
        ... on Team {
          ...Api::Serializer::OrganizationsDependency::TeamFragment
          ...Api::Serializer::OrganizationsDependency::SimpleTeamFragment
        }
      }
    }
  GRAPHQL

  context "graphql_team_hash" do
    test "returns the expected team data" do
      results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: false }, context: { viewer: @admin })
      graphql_output = T.unsafe(self).graphql_team(results.data.node)
      output = T.unsafe(self).team(@team)

      assert_equal output, graphql_output
    end

    test "returns the expected full team data" do
      results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
      graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)
      output = T.unsafe(self).team(@team, full: true)

      assert_equal output, graphql_output
    end

    test "returns the team data with notification_setting included" do
      results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
      graphql_output = T.unsafe(self).graphql_team(results.data.node)

      assert_includes graphql_output, "notification_setting"
    end

    test "parent_team hash included" do
      parent_team = create(:team, organization: @org, privacy: :closed)
      child_team = create(:team, organization: @org, privacy: :closed, parent_team_id: parent_team.id)

      results = Api::App::PlatformClient.query(TeamQuery, variables: { id: child_team.global_relay_id, includeFullTeamDetails: false }, context: { viewer: @admin })
      graphql_output = T.unsafe(self).graphql_team(results.data.node)
      output = T.unsafe(self).team(child_team)

      assert_equal output, graphql_output
    end

    context "organization hash" do
      test "included with full team_hash" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert graphql_output.key?("organization"), "should include organization key"
      end

      test "blog is included when present" do
        @org.profile_blog = "http://github.blog"
        @org.save

        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert_equal "http://github.blog", graphql_output["organization"]["blog"]
      end

      test "blog is empty string when no profile_blog is set but profile is present" do
        @org.profile_name = "profile name"
        @org.save

        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert_equal "", graphql_output["organization"]["blog"]
      end
    end

    context "members_count" do
      test "excluded when not full team_hash" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: false }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node)

        refute graphql_output.key?("members_count"), "should not include members_count key"
      end

      test "included for full team_hash" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert graphql_output.key?("members_count"), "should include members_count key"
      end

      test "counts immediate members" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @parent_team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert_equal @parent_team.members_scope(membership: :all).count, graphql_output["members_count"]
      end

      test "counts immediate and child team members" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @parent_team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert_equal @parent_team.members_scope.count, graphql_output["members_count"]
      end
    end

    context "repos_count" do
      test "excluded when not full team_hash" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: false }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node)

        refute graphql_output.key?("repos_count"), "should not include repositories_count key"
      end

      test "included for full team_hash" do
        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert graphql_output.key?("repos_count"), "should include repositories_count key"
      end

      test "counts directly assigned repositories" do
        @parent_team.add_repository(create(:repository, :minimal, owner: @org), :admin)
        @child_team.add_repository(create(:repository, :minimal, owner: @org), :admin)

        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @child_team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert_equal @child_team.repositories_scope(affiliation: :all).count, graphql_output["repos_count"]
      end

      test "counts direct and inherited repositories" do
        @parent_team.add_repository(create(:repository, :minimal, owner: @org), :admin)
        @child_team.add_repository(create(:repository, :minimal, owner: @org), :admin)

        results = Api::App::PlatformClient.query(TeamQuery, variables: { id: @child_team.global_relay_id, includeFullTeamDetails: true }, context: { viewer: @admin })
        graphql_output = T.unsafe(self).graphql_team(results.data.node, full: true)

        assert_equal @child_team.repositories_scope(affiliation: :all).count, graphql_output["repos_count"]
      end
    end
  end

  context "team_membership_hash" do
    test "for an invited team member" do
      invitee = create(:user, login: "invitee")
      @org.invite(invitee, inviter: @admin, teams: [@team])

      output = T.unsafe(self).team_membership(team: @team, user: invitee)

      assert_equal "pending", output["state"]
      assert_equal "member", output["role"]
    end

    test "for an invited team maintainer" do
      invitee    = create(:user, login: "invitee")
      invitation = @org.invite(invitee, inviter: @admin, teams: [@team])
      invitation.add_team(@team, inviter: @admin, role: :maintainer)

      output = T.unsafe(self).team_membership(team: @team, user: invitee)

      assert_equal "pending", output["state"]
      assert_equal "maintainer", output["role"]
    end

    test "for a team member" do
      team_member = create(:user, login: "team-member")
      @team.add_member(team_member)

      output = T.unsafe(self).team_membership(team: @team, user: team_member)

      assert_equal "active", output["state"]
      assert_equal "member", output["role"]
    end

    test "for a team maintainer" do
      team_maintainer = create(:user, login: "team-maintainer")
      @org.add_member(team_maintainer)
      @team.add_member(team_maintainer)
      @team.promote_maintainer(team_maintainer)

      output = T.unsafe(self).team_membership(team: @team, user: team_maintainer)

      assert_equal "active", output["state"]
      assert_equal "maintainer", output["role"]
    end

    test "for a child team member is membership is active" do
      team_member = create(:user, login: "team-member")
      @child_team.add_member(team_member)

      output = T.unsafe(self).team_membership(team: @parent_team, user: team_member)

      assert_equal "active", output["state"]
      assert_equal "member", output["role"]
    end

    test "for an unaffiliated user" do
      user = create(:user, login: "unaffiliated")

      output = T.unsafe(self).team_membership(team: @team, user: user)

      assert_equal "inactive", output["state"]
      assert_equal "unaffiliated", output["role"]
    end
  end

  context "#org_membership_hash" do
    test "includes the organization in the payload by default" do
      payload = T.unsafe(self).org_membership(@org, user: @admin)
      assert_includes payload, "organization"
    end

    test "omits the organization from the payload when options[:full] is false" do
      payload = T.unsafe(self).org_membership(@org, user: @admin, full: false)
      refute_includes payload, "organization"
    end
  end
end
