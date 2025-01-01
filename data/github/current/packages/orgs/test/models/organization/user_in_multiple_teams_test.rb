# encoding: utf-8
# typed: true
# frozen_string_literal: true

require "test_helper"

class OrganizationUserInMultipleTeamsTest < GitHub::TestCase
  fixtures do
    @owner = create(:user)
    @org   = create(:organization, admin: @owner, plan: "bronze")
    @team  = create(:team, organization: @org, permission: "admin")
    @team2 = create(:team, organization: @org, permission: "pull")
    @team3 = create(:team, organization: @org, permission: "pull")

    @org2  = create(:organization)
    @team3 = create(:team, organization: @org2, permission: "pull")

    @user     = create(:user)
    @pub_repo = create(:repository, :minimal, owner: @org)
    @repo     = create(:private_repository, :minimal, owner: @org)
    @repo2    = create(:private_repository, :minimal, owner: @org)
    @repo3    = create(:private_repository, :minimal, owner: @org)

    @team.add_member @user
    @team.add_repository @repo, :admin
    @team2.add_member @user
    @team2.add_repository @repo2, :pull
    @team3.add_member @user
    @team3.add_repository @repo3, :pull

    enable_feature_flag(:enterprise_teams_crud)
    @business = create(:business)
    @business.add_user_accounts([@user.id, @owner.id])

    @biz_org = create(:organization, admin: @owner, business: @business)
    @biz_org_team = create(:team, organization: @biz_org)
    @biz_org_team.add_member(@user)

    @business_team = create(:business_team, business: @business)
    @business_team.add_member(@user)
    @business_team.add_to_organizations(org_ids: [@biz_org.id])

    @business_team_all_orgs = create(:business_team, business: @business, organization_selection_type: :all)
    @business_team_all_orgs.add_member(@user)
  end

  setup do
    enable_feature_flag(:enterprise_teams_crud)
  end

  test "knows they are in the organization" do
    assert_equal [@org, @org2, @biz_org], @user.organizations
  end

  test "knows they are in all teams" do
    teams = [@team, @team2, @team3, @biz_org_team]
    assert_same_elements teams, @user.teams
  end

  context "find_team_by_slug" do
    test "returns nil for nonexistent teams" do
      assert_nil @org.find_team_by_slug("not-a-team")
    end

    test "finds a team that the viewer can see" do
      refute_nil @org.find_team_by_slug(@team.slug, visible_to: @user)
    end

    test "returns nil for teams that the viewer can't see" do
      @team.remove_member(@user)
      @team.privacy = :secret
      @team.save!

      assert_nil @org.find_team_by_slug(@team.slug, visible_to: @user)
    end

    test "finds a team without a viewing user" do
      refute_nil @org.find_team_by_slug(@team.slug)
    end
  end

  context "teams_for" do
    test "includes all of the teams the user is on" do
      assert_same_elements [@team, @team2], @org.teams_for(@user)
      assert_same_elements [@team3], @org2.teams_for(@user)
    end

    test "includes only the teams the user is on that the viewer can see if one is specified" do
      org         = create(:organization)
      team_member = create(:user, login: "team-member")
      viewer      = create(:user, login: "viewer")
      org.add_member(team_member)
      org.add_member(viewer)

      closed_team = create(:team, organization: org, name: "closed-team", privacy: :closed)
      closed_team.add_member(team_member)

      common_secret_team = create(:team, organization: org, name: "common-secret-team", privacy: :secret)
      common_secret_team.add_member(team_member)
      common_secret_team.add_member(viewer)

      uncommon_secret_team = create(:team, organization: org, name: "uncommon-secret-team", privacy: :secret)
      uncommon_secret_team.add_member(team_member)

      create(:team, organization: org, name: "empty-team", privacy: :closed)

      assert_same_elements [closed_team, common_secret_team], org.teams_for(team_member, viewer: viewer)
    end
  end

  context "visible_teams_for" do
    test "includes all of the org's teams for an owner" do
      assert_same_elements @org.teams, @org.visible_teams_for(@owner)
    end

    test "includes all of the org's teams for a Bot whose installation has permission on 'members'" do
      installation = make_integration_installation(
          target: @org, permissions: { "members" => :read })

      assert_same_elements @org.teams, @org.visible_teams_for(installation.bot)
    end

    test "doesn't automatically include the owners team for a regular member" do
      assert_same_elements [@team, @team2], @org.visible_teams_for(@user)
    end

    test "doesn’t include secret teams that the user isn’t a member of" do
      @org.add_member(@user)
      secret_team = create(:team, organization: @org, privacy: :secret)

      refute_includes @org.visible_teams_for(@user), secret_team
    end

    test "includes secret teams that the user is a member of" do
      @org.add_member(@user)
      secret_team = create(:team, organization: @org, privacy: :secret)
      secret_team.add_member(@user)

      assert_includes @org.visible_teams_for(@user), secret_team
    end

    test "includes secret teams for org owners" do
      secret_team = create(:team, organization: @org, privacy: :secret)
      org_admin   = create(:user)
      @org.add_admin(org_admin)

      assert_includes @org.visible_teams_for(org_admin), secret_team
    end

    test "doesn’t include deleted teams" do
      @org.add_member(@user)
      deleted_team = create(:team, organization: @org, name: "deleted-team", deleted: true)
      deleted_team.add_member(@user)

      refute_includes @org.visible_teams_for(@user), deleted_team
    end

    context "enterprise teams" do
      test "works as expected for non-business owned organization when with_business_teams:true" do
        teams = @org.teams
        assert_same_elements teams, @org.visible_teams_for(@owner, with_business_teams: true)
        assert_same_elements [@team, @team2], @org.visible_teams_for(@user, with_business_teams: true)
      end

      test "doesn’t include deleted teams when with_business_teams:true" do
        @org.add_member(@user)
        deleted_team = create(:team, organization: @org, name: "deleted-team", deleted: true)
        deleted_team.add_member(@user)

        refute_includes @org.visible_teams_for(@user, with_business_teams: true), deleted_team
      end

      test "excludes assigned to the org for an owner when with_business_teams:false" do
        teams = @biz_org.teams
        assert_same_elements teams, @biz_org.visible_teams_for(@owner)
      end

      test "includes assigned to the org for an owner when with_business_teams:true" do
        teams = @biz_org.teams + [@business_team, @business_team_all_orgs]
        assert_same_elements teams, @biz_org.visible_teams_for(@owner, with_business_teams: true)
      end

      test "excludes assigned to the org for a regular member when with_business_teams:false" do
        assert_same_elements [@biz_org_team], @biz_org.visible_teams_for(@user)
      end

      test "includes assigned to the org for a regular member when with_business_teams:true" do
        assert_same_elements [@biz_org_team, @business_team, @business_team_all_orgs], @biz_org.visible_teams_for(@user, with_business_teams: true)
      end

      test "includes all of the org's teams and business teams for a Bot whose installation has permission on 'members' when with_business_teams:true" do
        installation = make_integration_installation(
            target: @biz_org, permissions: { "members" => :read })
        assert_same_elements [@biz_org_team, @business_team, @business_team_all_orgs], @biz_org.visible_teams_for(installation.bot, with_business_teams: true)
      end

      test "only includes the direct org's teams for a Bot whose installation has permission on 'members' when with_business_teams:false" do
        installation = make_integration_installation(
            target: @biz_org, permissions: { "members" => :read })
        assert_same_elements @biz_org.teams, @biz_org.visible_teams_for(installation.bot)
      end

      test "doesn’t include secret teams that the user isn’t a member of when with_business_teams:true" do
        @biz_org.add_member(@user)
        secret_team = create(:team, organization: @biz_org, privacy: :secret)

        refute_includes @biz_org.visible_teams_for(@user, with_business_teams: true), secret_team
      end

      test "includes secret teams that the user is a member of when with_business_teams:true" do
        @biz_org.add_member(@user)
        secret_team = create(:team, organization: @biz_org, privacy: :secret)
        secret_team.add_member(@user)

        assert_includes @biz_org.visible_teams_for(@user, with_business_teams: true), secret_team
      end

      test "includes secret teams for org owners when with_business_teams:true" do
        secret_team = create(:team, organization: @biz_org, privacy: :secret)
        org_admin   = create(:user)
        @biz_org.add_admin(org_admin)

        assert_includes @biz_org.visible_teams_for(org_admin, with_business_teams: true), secret_team
      end
    end
  end

  test "can be completely removed from the organization" do
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @org.remove_member @user
    end
    @org.reload
    refute_includes @org.people, @user
    assert_equal @user, @user.reload
  end

  test "removes public membership when removed from an organization" do
    @org.publicize_member @user
    perform_enqueued_jobs(only: [RemoveOrgMemberJob, RevokeOrgMembershipAbilitiesJob]) do
      @org.remove_member @user
    end
    @org.reload
    refute_includes @org.people, @user
    refute_includes @org.public_members, @user
  end
end
