# typed: true
# frozen_string_literal: true

require "test_helper"

class Orgs::Domain::TeamsTest < GitHub::TestCase
  fixtures do
    @user = create(:user)

    enable_feature_flag(:enterprise_teams_crud)
    enable_feature_flag(:enterprise_teams_org_roles)
    @business = create(:business)
    @business.add_user_accounts([@user.id])

    @org = create(:organization, business: @business)
    @team = create(:team, organization: @org)

    @business_team = create(:business_team, business: @business)
    @business_team.add_member(@user, caller_type: :business_team)
    @business_team.add_to_organizations(org_ids: [@org.id])

    @business_team_all_orgs = create(:business_team, business: @business, organization_selection_type: :all)
    @business_team_all_orgs.add_member(@user, caller_type: :business_team)

    # org not affiliated with the business
    @other_org = create(:organization)

    @expect_biz_team_org_ids_query_count = 8
  end

  setup do
    enable_feature_flag(:enterprise_teams_crud)
    enable_feature_flag(:enterprise_teams_org_assignment)
  end

  sig { returns(Orgs::Domain::Teams) }
  def domain
    Orgs::Domain::Teams.new
  end

  context "by_id" do
    test "find a team" do
      assert_equal @team, domain.by_id(@team.id)
    end
  end

  context "business_team_ids_for_assigned_orgs" do
    test "finds business team ids for assigned orgs" do
      team_ids = domain.business_team_ids_for_assigned_orgs(organization_id: @org.id)
      assert_includes team_ids, @business_team.id
      assert_includes team_ids, @business_team_all_orgs.id
    end

    test "scopes lookup for orgs within the given business" do
      team_ids = domain.business_team_ids_for_assigned_orgs(organization_id: @other_org.id)
      assert_empty team_ids
    end
  end

  context "business_team_ids_for" do
    test "finds business team ids for a user" do
      team_ids = domain.business_team_ids_for(business_id: @business.id, user_id: @user.id)
      assert_includes team_ids, @business_team.id
      assert_includes team_ids, @business_team_all_orgs.id
    end
  end

  context "business_team_ids_with_assigned_orgs_for" do
    test "finds business team ids with assigned orgs for a user" do
      team_ids = domain.business_team_ids_with_assigned_orgs_for(user_id: @user.id, organization_id: @org.id)
      assert_includes team_ids, @business_team.id
      assert_includes team_ids, @business_team_all_orgs.id
    end

    test "scopes lookup for orgs within the given business" do
      team_ids = domain.business_team_ids_with_assigned_orgs_for(user_id: @user.id, organization_id: @other_org.id)
      assert_empty team_ids
    end

    test "does not return all org teams if the user is not in the team" do
      another_all_orgs_team = create(:business_team, business: @business, organization_selection_type: :all)
      team_ids = domain.business_team_ids_with_assigned_orgs_for(user_id: @user.id, organization_id: @org.id)
      refute_includes team_ids, another_all_orgs_team.id
    end
  end

  context "business_team_user_ids" do
    test "finds user_ids for business teams with assigned orgs for users" do
      user_ids = domain.business_team_user_ids(user_ids: [@user.id], organization_id: @org.id)
      assert_includes user_ids, @user.id
    end

    test "scopes lookup for orgs within the given business" do
      user_ids = domain.business_team_user_ids(user_ids: [@user.id], organization_id: @other_org.id)
      assert_empty user_ids
    end

    test "does not return user ids if user does not belong to a business team" do
      org = create(:organization, business: @business)
      team = create(:team, organization: org)
      user = create(:user)
      team.add_member(user, caller_type: :team)

      user_ids = domain.business_team_user_ids(user_ids: [user.id], organization_id: org.id)
      assert_empty user_ids
    end
  end

  context "business_team_org_ids_for_user" do
    test "finds org ids for business teams associated with user" do
      org_ids = assert_query_count(@expect_biz_team_org_ids_query_count) do
        domain.business_team_org_ids_for_user(user_id: @user.id)
      end
      assert_includes org_ids, @org.id
    end

    test "fetches org ids for business teams associated with user without increasing query count according to org count (10)" do
      10.times do
        create(:organization, business: @business)
      end

      org_ids = assert_query_count(@expect_biz_team_org_ids_query_count) do
        domain.business_team_org_ids_for_user(user_id: @user.id)
      end
    end

    test "takes an optional min_action parameter which filters out orgs with a default permission higher than the user access level" do
      org_with_read_default = create(:organization, business: @business, name: "org-default-read")

      org_with_write_default = create(:organization, business: @business, name: "org-default-write")
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        org_with_write_default.update_default_repository_permission(:write, actor: @org.owner)
      end

      org_with_admin_default = create(:organization, business: @business, name: "org-default-admin")
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        org_with_admin_default.update_default_repository_permission(:admin, actor: @org.owner)
      end

      org_with_none_default = create(:organization, business: @business, name: "org-default-none")
      perform_enqueued_jobs(only: SyncOrganizationDefaultRepositoryPermissionJob) do
        org_with_none_default.update_default_repository_permission(:none, actor: @org.owner)
      end

      read_org_ids = domain.business_team_org_ids_for_user(user_id: @user.id, min_action: :read)
      assert_includes read_org_ids, org_with_admin_default.id
      assert_includes read_org_ids, org_with_write_default.id
      assert_includes read_org_ids, org_with_read_default.id
      refute_includes read_org_ids, org_with_none_default.id

      default_org_ids = domain.business_team_org_ids_for_user(user_id: @user.id)
      assert_includes default_org_ids, org_with_admin_default.id
      assert_includes default_org_ids, org_with_write_default.id
      assert_includes default_org_ids, org_with_read_default.id
      refute_includes default_org_ids, org_with_none_default.id

      write_org_ids = domain.business_team_org_ids_for_user(user_id: @user.id, min_action: :write)
      assert_includes write_org_ids, org_with_admin_default.id
      assert_includes write_org_ids, org_with_write_default.id
      refute_includes write_org_ids, org_with_read_default.id
      refute_includes write_org_ids, org_with_none_default.id

      admin_org_ids = domain.business_team_org_ids_for_user(user_id: @user.id, min_action: :admin)
      assert_includes admin_org_ids, org_with_admin_default.id
      refute_includes admin_org_ids, org_with_write_default.id
      refute_includes admin_org_ids, org_with_read_default.id
      refute_includes admin_org_ids, org_with_none_default.id
    end
  end

  context "find_team_in_organization" do
    test "finds regular team by id associated with organization" do
      found_team = domain.find_team_in_organization(team_id: @team.id, organization_id: @org.id)
      assert_equal @team.id, found_team&.id
    end

    test "finds regular team by id associated with organization when slug is also provided" do
      found_team = domain.find_team_in_organization(team_id: @team.id, team_slug: "something", organization_id: @org.id)
      assert_equal @team.id, found_team&.id
    end

    test "finds regular team by id associated with organization when empty slug is also provided" do
      found_team = domain.find_team_in_organization(team_id: @team.id, team_slug: "", organization_id: @org.id)
      assert_equal @team.id, found_team&.id
    end

    test "does not find regular team by id not associated with organization" do
      found_team = domain.find_team_in_organization(team_id: @team.id, organization_id: @other_org.id)
      assert_nil found_team
    end

    test "finds business team by id associated with organization when organization_selection_type: selected" do
      found_team = domain.find_team_in_organization(team_id: @business_team.id, organization_id: @org.id)
      assert_equal @business_team.id, found_team&.id
    end

    test "finds business team by id associated with organization when organization_selection_type: all" do
      found_team = domain.find_team_in_organization(team_id: @business_team_all_orgs.id, organization_id: @org.id)
      assert_equal @business_team_all_orgs.id, found_team&.id
    end

    test "does not find business team by id not associated with organization" do
      found_team = domain.find_team_in_organization(team_id: @business_team.id, organization_id: @other_org.id)
      assert_nil found_team
    end

    test "finds regular team by slug associated with organization" do
      found_team = domain.find_team_in_organization(team_slug: @team.slug, organization_id: @org.id)
      assert_equal @team.id, found_team&.id
    end

    test "prioritize team by slug when negative id is also passed associated with organization" do
      found_team = domain.find_team_in_organization(team_slug: @team.slug, team_id: -1, organization_id: @org.id)
      assert_equal @team.id, found_team&.id
    end

    test "does not find regular team by slug not associated with organization" do
      found_team = domain.find_team_in_organization(team_slug: @team.slug, organization_id: @other_org.id)
      assert_nil found_team
    end

    test "finds business team by slug associated with organization when organization_selection_type: selected" do
      found_team = domain.find_team_in_organization(team_slug: @business_team.slug, organization_id: @org.id)
      assert_equal @business_team.id, found_team&.id
    end

    test "finds business team by slug associated with organization when organization_selection_type: all" do
      found_team = domain.find_team_in_organization(team_slug: @business_team_all_orgs.slug, organization_id: @org.id)
      assert_equal @business_team_all_orgs.id, found_team&.id
    end

    test "does not find business team by slug not associated with organization" do
      found_team = domain.find_team_in_organization(team_slug: @business_team.slug, organization_id: @other_org.id)
      assert_nil found_team
    end

    test "does not find team by slug not associated with organization" do
      found_team = domain.find_team_in_organization(team_slug: @business_team.slug, organization_id: @other_org.id)
      assert_nil found_team
    end
  end

  context "teams_for_repo" do
    test "finds business team ids for a repo when no team_ids is specified" do
      repo = create(:repository, owner: @org, name: "best-repo")
      @business_team.add_repository(repo, :admin)
      teams = domain.teams_for_repo(repo_id: repo.id)
      assert_includes teams, @business_team
      refute_includes teams, @business_team_all_orgs
    end

    test "finds and filters business team ids for a repo when team_ids is specified" do
      repo = create(:repository, owner: @org, name: "best-repo")
      @business_team.add_repository(repo, :admin)
      @business_team_all_orgs.add_repository(repo, :admin)
      teams = domain.teams_for_repo(repo_id: repo.id, team_ids: [@business_team.id])
      assert_includes teams, @business_team
      refute_includes teams, @business_team_all_orgs
    end

    test "finds and filters all team ids for a repo when team_ids is specified" do
      repo = create(:repository, owner: @org, name: "best-repo")
      @business_team.add_repository(repo, :admin)
      @business_team_all_orgs.add_repository(repo, :admin)
      @team.add_repository(repo, :admin)
      teams = domain.teams_for_repo(repo_id: repo.id, team_ids: [@business_team.id, @team.id])
      assert_includes teams, @business_team
      assert_includes teams, @team
      refute_includes teams, @business_team_all_orgs
    end
  end
end
