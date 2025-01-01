# typed: true
# frozen_string_literal: true

require "test_helper"

class RoleAssignments::FetchEnterpriseRoleAssignmentsTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    enable_feature_flag(:custom_enterprise_role_feature)
    enable_feature_flag(:enterprise_teams_crud)

    @business = create(:business)

    @user = create(:user)
    create(:business_user_account, user: @user, business: @business)
    @business_team = create(:business_team, business: @business)

    @enterprise_role1 = EnterpriseRole.create!(name: "Enterprise Role 1", owner: @business, owner_type: "Business", description: "Desc")
  end

  context ".paginate_user_role_assignments" do
    test "includes directly assigned users" do
      Permissions::Granters::RoleGranter.new(actor: @user, target: @business, role: @enterprise_role1).grant!

      user_role_assignments = assert_query_count(4, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @enterprise_role1.display_name, role_assignment.role.name
      assert_equal @enterprise_role1.description, role_assignment.role.description
      assert_equal @enterprise_role1.octicon, role_assignment.role.octicon
    end

    test "includes users who are indirectly assigned via business teams" do
      @business_team.add_member(@user, caller_type: :business_team)
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: @enterprise_role1).grant!

      user_role_assignments = assert_query_count(6, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      refute role_assignment.directly_assigned
      assert_equal @enterprise_role1.display_name, role_assignment.role.name
      assert_equal @enterprise_role1.description, role_assignment.role.description
      assert_equal @enterprise_role1.octicon, role_assignment.role.octicon

      assert_equal 1, role_assignment.indirect_assignments.size
      indirect_assignment = T.must(role_assignment.indirect_assignments.first)
      assert_equal @business_team.name, indirect_assignment.team_name
      assert_equal "BusinessTeam", indirect_assignment.type
      assert_equal "/enterprises/#{@business.slug}/teams/#{@business_team.slug}", indirect_assignment.team_url
    end

    test "returns an empty array when feature is disabled" do
      @business_team.add_member(@user)
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: @enterprise_role1).grant!
      # we should not return results when assignments exist but feature is disabled
      disable_feature_flag(:custom_enterprise_role_feature)
      disable_feature_flag(:erp_staffship)
      disable_feature_flag(:erp_preview)

      user_role_assignments = assert_query_count(0, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 1)
      end

      assert_empty user_role_assignments
    end

    test "user assigned both directly and indirectly" do
      @business_team.add_member(@user, caller_type: :business_team)
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: @enterprise_role1).grant!
      Permissions::Granters::RoleGranter.new(actor: @user, target: @business, role: @enterprise_role1).grant!

      user_role_assignments = assert_query_count(6, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_equal @enterprise_role1.display_name, role_assignment.role.name
      assert_equal @enterprise_role1.description, role_assignment.role.description
      assert_equal @enterprise_role1.octicon, role_assignment.role.octicon

      assert_equal 1, role_assignment.indirect_assignments.size
      indirect_assignment = T.must(role_assignment.indirect_assignments.first)
      assert_equal @business_team.name, indirect_assignment.team_name
      assert_equal "BusinessTeam", indirect_assignment.type
      assert_equal "/enterprises/#{@business.slug}/teams/#{@business_team.slug}", indirect_assignment.team_url
    end

    test "user with multiple indirect assignment sources" do
      business_teams = create_list(:business_team, 5, business: @business)
      business_teams.each do |team|
        team.add_member(@user, caller_type: :business_team)
        Permissions::Granters::RoleGranter.new(actor: team, target: @business, role: @enterprise_role1).grant!
      end

      user_role_assignments = assert_query_count(6, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      refute role_assignment.directly_assigned
      assert_equal @enterprise_role1.display_name, role_assignment.role.name
      assert_equal @enterprise_role1.description, role_assignment.role.description
      assert_equal @enterprise_role1.octicon, role_assignment.role.octicon

      assert_equal 5, role_assignment.indirect_assignments.size
      assert_same_elements business_teams.map(&:name), role_assignment.indirect_assignments.map(&:team_name)
    end

    test "paginates multiple results" do
      users = create_list(:user, 5, business_id: @business.id)
      users.each do |user|
        Permissions::Granters::RoleGranter.new(actor: user, target: @business, role: @enterprise_role1).grant!
      end

      first_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      second_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      third_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      RoleAssignments::FetchRoleAssignments.stub_const(:PAGE_SIZE, 3) do
        assert_query_count(4, ignore_feature_flags: true) do
          first_page = RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 1)
        end
        assert_query_count(4, ignore_feature_flags: true) do
          second_page = RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 2)
        end
        assert_query_count(3, ignore_feature_flags: true) do
          third_page = RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_user_role_assignments(page: 3)
        end
      end

      assert_equal 3, first_page.size
      assert_equal 2, second_page.size
      assert_empty third_page

      sorted_names = users.map(&:login).sort
      assert_same_elements sorted_names[...3], first_page.map { |assignment| assignment.actor.name }
      assert_same_elements sorted_names[3...], second_page.map { |assignment| assignment.actor.name }
    end

    test "filters users by login when query provided" do
      user1 = create(:user, login: "alice")
      user2 = create(:user, login: "bob")
      user3 = create(:user, login: "carol")

      [user1, user2, user3].each do |user|
        Permissions::Granters::RoleGranter.new(actor: user, target: @business, role: @enterprise_role1).grant!
      end

      # Filtering with "ali" should match only alice
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "ali")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_equal 1, assignments.size
        assert_equal 1, fetcher.total_user_role_assignments
        assignment = T.must(assignments.first)
        assert_equal "alice", assignment.actor.description
      end

      # Filtering with "o" should match bob and carol
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "o")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_equal 2, assignments.size
        assert_equal 2, fetcher.total_user_role_assignments
        assert_equal "bob", T.must(assignments[0]).actor.description
        assert_equal "carol", T.must(assignments[1]).actor.description
      end

      # Filtering with a non-matching query returns an empty array
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "zzz")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_empty assignments
        assert_equal 0, fetcher.total_user_role_assignments
      end
    end

    test "filters users by profile name when query provided" do
      user1 = create(:user, :with_profile, profile_name: "alice", login: "1")
      user2 = create(:user, :with_profile, profile_name: "bob", login: "2")
      user3 = create(:user, :with_profile, profile_name: "carol", login: "3")

      [user1, user2, user3].each do |user|
        Permissions::Granters::RoleGranter.new(actor: user, target: @business, role: @enterprise_role1).grant!
      end

      # Filtering with "ali" should match only alice
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "ali")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_equal 1, assignments.size
        assert_equal 1, fetcher.total_user_role_assignments
        assignment = T.must(assignments.first)
        assert_equal "alice", assignment.actor.name
      end

      # Filtering with "o" should match bob and carol
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "o")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_equal 2, assignments.size
        assert_equal 2, fetcher.total_user_role_assignments
        assert_equal "bob", T.must(assignments[0]).actor.name
        assert_equal "carol", T.must(assignments[1]).actor.name
      end

      # Filtering with a non-matching query returns an empty array
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "zzz")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_empty assignments
        assert_equal 0, fetcher.total_user_role_assignments
      end
    end
  end

  context ".paginate_business_team_role_assignments" do
    test "includes directly assigned teams" do
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: @enterprise_role1).grant!

      team_role_assignments = assert_query_count(3, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_business_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      assert_equal @business_team.name, actor_role_assignment.actor.name
      assert_equal @business_team.description, actor_role_assignment.actor.description
      assert_equal "BusinessTeam", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @enterprise_role1.display_name, role_assignment.role.name
      assert_equal @enterprise_role1.description, role_assignment.role.description
      assert_equal @enterprise_role1.octicon, role_assignment.role.octicon
    end

    test "returns an empty array when feature is disabled" do
      Permissions::Granters::RoleGranter.new(actor: @business_team, target: @business, role: @enterprise_role1).grant!
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship)
      disable_feature_flag(:erp_preview)

      team_role_assignments = assert_query_count(0, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_business_team_role_assignments(page: 1)
      end

      assert_empty team_role_assignments
    end

    test "paginates multiple results" do
      business_teams = create_list(:business_team, 5, business: @business)
      business_teams.each do |team|
        Permissions::Granters::RoleGranter.new(actor: team, target: @business, role: @enterprise_role1).grant!
      end

      first_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      second_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      third_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      RoleAssignments::FetchRoleAssignments.stub_const(:PAGE_SIZE, 3) do
        assert_query_count(3, ignore_feature_flags: true) do
          first_page = RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_business_team_role_assignments(page: 1)
        end
        assert_query_count(3, ignore_feature_flags: true) do
          second_page = RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_business_team_role_assignments(page: 2)
        end
        assert_query_count(3, ignore_feature_flags: true) do
          third_page = RoleAssignments::FetchRoleAssignments.new(target: @business).paginate_business_team_role_assignments(page: 3)
        end
      end

      assert_equal 3, first_page.size
      assert_equal 2, second_page.size
      assert_empty third_page

      sorted_names = business_teams.map(&:name).sort
      assert_same_elements sorted_names[...3], first_page.map { |assignment| assignment.actor.name }
      assert_same_elements sorted_names[3..], second_page.map { |assignment| assignment.actor.name }
    end

    test "filters teams by name when query provided" do
      team1 = create(:business_team, business: @business, name: "alice")
      team2 = create(:business_team, business: @business, name: "bob")
      team3 = create(:business_team, business: @business, name: "carol")

      [team1, team2, team3].each do |team|
        Permissions::Granters::RoleGranter.new(actor: team, target: @business, role: @enterprise_role1).grant!
      end

      # Filtering with "ali" should match only alice
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "ali")
        assignments = fetcher.paginate_business_team_role_assignments(page: 1)
        assert_equal 1, assignments.size
        assert_equal 1, fetcher.total_business_team_role_assignments
        assignment = T.must(assignments.first)
        assert_equal "alice", assignment.actor.name
      end

      # Filtering with "o" should match bob and carol
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "o")
        assignments = fetcher.paginate_business_team_role_assignments(page: 1)
        assert_equal 2, assignments.size
        assert_equal 2, fetcher.total_business_team_role_assignments
        assert_equal "bob", T.must(assignments[0]).actor.name
        assert_equal "carol", T.must(assignments[1]).actor.name
      end

      # Filtering with a non-matching query returns an empty array
      assert_query_count(4, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @business, query: "zzz")
        assignments = fetcher.paginate_business_team_role_assignments(page: 1)
        assert_empty assignments
        assert_equal 0, fetcher.total_business_team_role_assignments
      end
    end
  end
end

class RoleAssignments::FetchOrgRoleAssignmentsTest < GitHub::TestCase
  include FineGrainedPermissionsTestHelper

  fixtures do
    enable_feature_flag(:enterprise_teams_org_roles)

    @business = create(:business)
    @org = create(:business_plus_organization, business: @business)

    @user = create(:user)
    create(:business_user_account, user: @user, business: @business)
    @team = create(:team, organization: @org, description: "Team 1")

    @org_role = OrganizationRole.create!(name: "Org Role 1", owner: @org, owner_type: "Organization", description: "Desc")
    @predefined_org_role = OrganizationRole.all_repo_admin_role
  end

  context ".paginate_user_role_assignments" do
    test "includes directly assigned users" do
      Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @org_role).grant!

      expected_count = (GitHub.enterprise? || TestEnv.test_all_features?) ? 6 : 5
      user_role_assignments = assert_query_count(expected_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon
    end

    test "uses predefined role's display name" do
      Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @predefined_org_role).grant!

      expected_count = (GitHub.enterprise? || TestEnv.test_all_features?) ? 6 : 5
      user_role_assignments = assert_query_count(expected_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @predefined_org_role.display_name, role_assignment.role.name
      assert_equal @predefined_org_role.description, role_assignment.role.description
      assert_equal @predefined_org_role.octicon, role_assignment.role.octicon
    end

    test "includes users who are indirectly assigned via teams" do
      @team.add_member(@user)
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 9 : 8
      user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      refute role_assignment.directly_assigned
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon

      assert_equal 1, role_assignment.indirect_assignments.size
      indirect_assignment = T.must(role_assignment.indirect_assignments.first)
      assert_equal @team.name, indirect_assignment.team_name
      assert_equal "Team", indirect_assignment.type
      assert_equal "/orgs/#{@org.display_login}/teams/#{@team.slug}", indirect_assignment.team_url
    end

    test "includes users who are indirectly assigned via business teams" do
      enable_feature_flag(:enterprise_teams_crud)

      business_team = create(:business_team, business: @business)
      business_team.add_member(@user, caller_type: :business_team)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 9 : 8
      user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      refute role_assignment.directly_assigned
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon

      assert_equal 1, role_assignment.indirect_assignments.size
      indirect_assignment = T.must(role_assignment.indirect_assignments.first)
      assert_equal business_team.name, indirect_assignment.team_name
      assert_equal "BusinessTeam", indirect_assignment.type
      assert_equal "/enterprises/#{@business.slug}/teams/#{business_team.slug}", indirect_assignment.team_url
    end

    test "includes team and business team assignments together" do
      enable_feature_flag(:enterprise_teams_crud)

      business_team = create(:business_team, business: @business)
      business_team.add_member(@user, caller_type: :business_team)
      @team.add_member(@user)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!
      team_org_role = OrganizationRole.create!(name: "Org Role 2", owner: @org, owner_type: "Organization", description: "Desc")
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: team_org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 9 : 8
      user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal 2, actor_role_assignment.role_assignments.size
    end

    test "excludes users who are indirectly assigned via business teams when business teams are disabled" do
      enable_feature_flag(:enterprise_teams_crud)

      business_team = create(:business_team, business: @business)
      business_team.add_member(@user)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship)
      disable_feature_flag(:erp_preview)

      expected_query_count = TestEnv.test_all_features? ? 5 : 4
      user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_empty user_role_assignments
    end

    test "user assigned both directly and indirectly" do
      @team.add_member(@user)
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!
      Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: @org_role).grant!

      expected_count = (GitHub.enterprise? || TestEnv.test_all_features?) ? 8 : 7
      user_role_assignments = assert_query_count(expected_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon

      assert_equal 1, role_assignment.indirect_assignments.size
      indirect_assignment = T.must(role_assignment.indirect_assignments.first)
      assert_equal @team.name, indirect_assignment.team_name
      assert_equal "Team", indirect_assignment.type
      assert_equal "/orgs/#{@org.display_login}/teams/#{@team.slug}", indirect_assignment.team_url
    end

    test "user with multiple indirect assignment sources" do
      teams = create_list(:team, 5, organization: @org)
      teams.each do |team|
        team.add_member(@user)
        Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @org_role).grant!
      end

      if GitHub.flipper[:enterprise_teams_crud].enabled?
        teams << business_team = create(:business_team, business: @business)
        business_team.add_member(@user, caller_type: :business_team)
        Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!
      end

      expected_query_count = (TestEnv.test_all_features? || TestEnv.test_all_features?) ? 8 : 7
      user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_equal 1, user_role_assignments.size
      actor_role_assignment = T.must(user_role_assignments.first)

      assert_equal @user.name, actor_role_assignment.actor.name
      assert_equal @user.display_login, actor_role_assignment.actor.description
      assert_equal "User", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      refute role_assignment.directly_assigned
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon

      assigned_teams = role_assignment.indirect_assignments.map(&:team_name)
      assert_equal teams.size, role_assignment.indirect_assignments.size
      assert_same_elements teams.map(&:name), assigned_teams
    end

    test "returns an empty array when feature is disabled" do
      Business.any_instance.expects(:enterprise_teams_org_roles_supported?).returns(false)
      @team.add_member(@user)
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!

      user_role_assignments = assert_query_count(1, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
      end

      assert_empty user_role_assignments
    end

    test "paginates multiple results" do
      users = create_list(:user, 5, business_id: @business.id)
      users.each do |user|
        Permissions::Granters::RoleGranter.new(actor: user, target: @org, role: @org_role).grant!
      end

      first_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      second_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      third_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      RoleAssignments::FetchRoleAssignments.stub_const(:PAGE_SIZE, 3) do
        expected_query_count = (GitHub.enterprise? || TestEnv.test_all_features?) ? 6 : 5
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          first_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
        end
        expected_query_count = TestEnv.test_all_features? ? 6 : 5
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          second_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 2)
        end
        expected_query_count = TestEnv.test_all_features? ? 5 : 4
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          third_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 3)
        end
      end

      assert_equal 3, first_page.size
      assert_equal 2, second_page.size
      assert_empty third_page

      sorted_names = users.map(&:login).sort
      assert_same_elements sorted_names[...3], first_page.map { |assignment| assignment.actor.name }
      assert_same_elements sorted_names[3...], second_page.map { |assignment| assignment.actor.name }
    end

    test "filters users by login when query provided" do
      user1 = create(:user, login: "alice")
      user2 = create(:user, login: "bob")
      user3 = create(:user, login: "carol")

      [user1, user2, user3].each do |user|
        Permissions::Granters::RoleGranter.new(actor: user, target: @org, role: @org_role).grant!
      end

      expected_query_count = 6

      # Filtering with "ali" should match only alice
      assert_max_query_count(expected_query_count, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @org, query: "ali")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_equal 1, assignments.size
        assert_equal 1, fetcher.total_user_role_assignments
        assignment = T.must(assignments.first)
        assert_equal "alice", assignment.actor.description
      end

      # Filtering with "o" should match bob and carol
      assert_max_query_count(expected_query_count, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @org, query: "o")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_equal 2, assignments.size
        assert_equal 2, fetcher.total_user_role_assignments
        assert_equal "bob", T.must(assignments[0]).actor.description
        assert_equal "carol", T.must(assignments[1]).actor.description
      end

      # Filtering with a non-matching query returns an empty array
      assert_max_query_count(expected_query_count, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @org, query: "zzz")
        assignments = fetcher.paginate_user_role_assignments(page: 1)
        assert_empty assignments
        assert_equal 0, fetcher.total_user_role_assignments
      end
    end

    context "nested teams" do
      test "includes users who are indirectly assigned through child team inheritance" do
        parent_team = create(:public_team, organization: @org, name: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team")
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!
        child_team.add_member(@user)
        refute parent_team.member?(@user)

        expected_query_count = TestEnv.test_all_features? ? 8 : 7
        user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
        end

        assert_equal 1, user_role_assignments.size
        actor_role_assignment = T.must(user_role_assignments.first)
        assert_equal @user.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal parent_team.name, indirect_assignment.team_name
      end

      test "includes users assigned through grandchild team inheritance" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")
        Permissions::Granters::RoleGranter.new(actor: grandparent_team, target: @org, role: @org_role).grant!
        child_team.add_member(@user)

        expected_query_count = TestEnv.test_all_features? ? 8 : 7
        user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
        end

        assert_equal 1, user_role_assignments.size
        actor_role_assignment = T.must(user_role_assignments.first)
        assert_equal @user.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal grandparent_team.name, indirect_assignment.team_name
      end

      test "includes users assigned with multiple indirect assignments via nested teams" do
        parent_team = create(:public_team, organization: @org, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!
        Permissions::Granters::RoleGranter.new(actor: child_team, target: @org, role: @org_role).grant!
        child_team.add_member(@user)

        expected_query_count = TestEnv.test_all_features? ? 8 : 7
        user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
        end

        assert_equal 1, user_role_assignments.size
        actor_role_assignment = T.must(user_role_assignments.first)
        assert_equal @user.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 2, role_assignment.indirect_assignments.size
        assert_includes role_assignment.indirect_assignments.map(&:team_name), parent_team.name
        assert_includes role_assignment.indirect_assignments.map(&:team_name), child_team.name
      end

      test "excludes as indirect source any ancestors of the directly assigned team" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")

        # parent team directly assigned role
        # child team inherits role from parent team
        # grandparent team is not assigned the role
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!
        child_team.add_member(@user)

        expected_query_count = TestEnv.test_all_features? ? 8 : 7
        user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
        end

        assert_equal 1, user_role_assignments.size
        actor_role_assignment = T.must(user_role_assignments.first)
        assert_equal @user.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        refute_equal grandparent_team.name, indirect_assignment.team_name
      end

      test "does not duplicate indirect sources when user is assigned to descendant teams" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")

        Permissions::Granters::RoleGranter.new(actor: grandparent_team, target: @org, role: @org_role).grant!
        grandparent_team.add_member(@user)
        parent_team.add_member(@user)
        child_team.add_member(@user)

        expected_query_count = TestEnv.test_all_features? ? 8 : 7
        user_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_user_role_assignments(page: 1)
        end

        assert_equal 1, user_role_assignments.size
        actor_role_assignment = T.must(user_role_assignments.first)
        assert_equal @user.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal grandparent_team.name, indirect_assignment.team_name
      end
    end
  end

  context ".paginate_business_team_role_assignments" do
    test "includes directly assigned business teams" do
      enable_feature_flag(:enterprise_teams_crud)
      business_team = create(:business_team, business: @business)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 6 : 5
      team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      assert_equal business_team.name, actor_role_assignment.actor.name
      assert_equal business_team.description, actor_role_assignment.actor.description
      assert_equal "BusinessTeam", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon
    end

    test "includes directly assigned business teams for an org selection" do
      enable_feature_flag(:enterprise_teams_crud)
      business_team = create(:business_team, business: @business, organization_selection_type: :selected)
      # it is not currently a requirement for the business team to be associated with the org
      # BusinessTeamOrgAssignment.create!(business_team: business_team, organization: @org)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 6 : 5
      team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      assert_equal business_team.name, actor_role_assignment.actor.name
      assert_equal business_team.description, actor_role_assignment.actor.description
      assert_equal "BusinessTeam", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon
    end

    test "excludes directly assigned teams" do
      enable_feature_flag(:enterprise_teams_crud)
      business_team = create(:business_team, business: @business)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 6 : 5
      team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      refute_equal @team.name, actor_role_assignment.actor.name
    end

    test "returns an empty array when business teams are disabled" do
      enable_feature_flag(:enterprise_teams_crud)
      business_team = create(:business_team, business: @business)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship)
      disable_feature_flag(:erp_preview)

      team_role_assignments = assert_query_count(1, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 1)
      end

      assert_empty team_role_assignments
    end

    test "returns an empty array when feature is disabled" do
      Business.any_instance.expects(:enterprise_teams_org_roles_supported?).returns(false)
      enable_feature_flag(:enterprise_teams_crud)

      business_team = create(:business_team, business: @business)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!

      team_role_assignments = assert_query_count(1, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 1)
      end

      assert_empty team_role_assignments
    end

    test "paginates multiple results" do
      enable_feature_flag(:enterprise_teams_crud)

      business_teams = create_list(:business_team, 5, business: @business)
      business_teams.each do |team|
        Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @org_role).grant!
      end

      first_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      second_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      third_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      RoleAssignments::FetchRoleAssignments.stub_const(:PAGE_SIZE, 3) do
        expected_query_count = TestEnv.test_all_features? ? 6 : 5
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          first_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 1)
        end
        expected_query_count = TestEnv.test_all_features? ? 5 : 4
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          second_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 2)
        end
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          third_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_business_team_role_assignments(page: 3)
        end
      end

      assert_equal 3, first_page.size
      assert_equal 2, second_page.size
      assert_empty third_page

      sorted_names = business_teams.map(&:name).sort
      assert_same_elements sorted_names[...3], first_page.map { |assignment| assignment.actor.name }
      assert_same_elements sorted_names[3..], second_page.map { |assignment| assignment.actor.name }
    end
  end

  context ".paginate_team_role_assignments" do
    test "includes directly assigned teams" do
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 9 : 8
      team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      assert_equal @team.name, actor_role_assignment.actor.name
      assert_equal @team.description, actor_role_assignment.actor.description
      assert_equal "Team", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon
    end

    test "includes directly assigned business teams" do
      enable_feature_flag(:enterprise_teams_crud)
      business_team = create(:business_team, business: @business)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!

      expected_query_count = TestEnv.test_all_features? ? 6 : 5
      team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      assert_equal business_team.name, actor_role_assignment.actor.name
      assert_equal business_team.description, actor_role_assignment.actor.description
      assert_equal "BusinessTeam", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon
    end

    test "excludes directly assigned business teams when business teams are disabled" do
      enable_feature_flag(:enterprise_teams_crud)
      business_team = create(:business_team, business: @business)
      Permissions::Granters::RoleGranter.new(actor: business_team, target: @org, role: @org_role).grant!
      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!
      disable_feature_flag(:enterprise_teams_crud)
      disable_feature_flag(:erp_staffship)
      disable_feature_flag(:erp_preview)

      expected_query_count = TestEnv.test_all_features? ? 9 : 8
      team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
      end

      assert_equal 1, team_role_assignments.size
      actor_role_assignment = T.must(team_role_assignments.first)

      assert_equal @team.name, actor_role_assignment.actor.name
      assert_equal @team.description, actor_role_assignment.actor.description
      assert_equal "Team", actor_role_assignment.actor.type

      role_assignment = T.must(actor_role_assignment.role_assignments.first)
      assert role_assignment.directly_assigned
      assert_empty role_assignment.indirect_assignments
      assert_equal @org_role.display_name, role_assignment.role.name
      assert_equal @org_role.description, role_assignment.role.description
      assert_equal @org_role.octicon, role_assignment.role.octicon
    end

    test "returns an empty array when feature is disabled" do
      Business.any_instance.expects(:enterprise_teams_org_roles_supported?).returns(false)

      Permissions::Granters::RoleGranter.new(actor: @team, target: @org, role: @org_role).grant!

      team_role_assignments = assert_query_count(1, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
      end

      assert_empty team_role_assignments
    end

    test "paginates multiple results" do
      teams = create_list(:team, 5, organization: @org)
      teams.each do |team|
        Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @org_role).grant!
      end

      first_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      second_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      third_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
      RoleAssignments::FetchRoleAssignments.stub_const(:PAGE_SIZE, 3) do
        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          first_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end
        expected_query_count = TestEnv.test_all_features? ? 8 : 7
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          second_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 2)
        end
        assert_query_count(expected_query_count, ignore_feature_flags: true) do
          third_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 3)
        end
      end

      assert_equal 3, first_page.size
      assert_equal 2, second_page.size
      assert_empty third_page

      sorted_names = teams.map(&:name).sort
      assert_same_elements sorted_names[...3], first_page.map { |assignment| assignment.actor.name }
      assert_same_elements sorted_names[3..], second_page.map { |assignment| assignment.actor.name }
    end

    test "filters teams by name when query provided" do
      enable_feature_flag(:enterprise_teams_crud)

      team1 = create(:team, organization: @org, name: "alice")
      team2 = create(:team, organization: @org, name: "bob")
      team3 = create(:business_team, business: @business, name: "carol")

      [team1, team2, team3].each do |team|
        Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @org_role).grant!
      end

      expected_query_count = 10

      # Filtering with "ali" should match only alice
      assert_max_query_count(expected_query_count, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @org, query: "ali")
        assignments = fetcher.paginate_team_role_assignments(page: 1)
        assert_equal 1, assignments.size
        assert_equal 1, fetcher.total_team_role_assignments
        assignment = T.must(assignments.first)
        assert_equal "alice", assignment.actor.name
      end

      # Filtering with "o" should match bob and carol
      assert_max_query_count(expected_query_count, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @org, query: "o")
        assignments = fetcher.paginate_team_role_assignments(page: 1)
        assert_equal 2, assignments.size
        assert_equal 2, fetcher.total_team_role_assignments
        assert_equal "bob", T.must(assignments[0]).actor.name
        assert_equal "carol", T.must(assignments[1]).actor.name
      end

      # Filtering with a non-matching query returns an empty array
      assert_max_query_count(expected_query_count, ignore_feature_flags: true) do
        fetcher = RoleAssignments::FetchRoleAssignments.new(target: @org, query: "zzz")
        assignments = fetcher.paginate_team_role_assignments(page: 1)
        assert_empty assignments
        assert_equal 0, fetcher.total_team_role_assignments
      end
    end

    context "nested teams" do
      test "includes teams assigned through child team inheritance" do
        parent_team = create(:public_team, organization: @org, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!

        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end

        assert_equal 2, team_role_assignments.size
        actor_role_assignment = team_role_assignments.find { |a| a.actor.name == child_team.name }
        assert_equal child_team.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal parent_team.name, indirect_assignment.team_name
      end

      test "includes teams assigned through grandchild team inheritance" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")
        Permissions::Granters::RoleGranter.new(actor: grandparent_team, target: @org, role: @org_role).grant!

        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end

        assert_equal 3, team_role_assignments.size
        actor_role_assignment = team_role_assignments.find { |a| a.actor.name == child_team.name }
        assert_equal child_team.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal grandparent_team.name, indirect_assignment.team_name
      end

      test "includes multiple assignment sources" do
        parent_team = create(:public_team, organization: @org, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!
        Permissions::Granters::RoleGranter.new(actor: child_team, target: @org, role: @org_role).grant!

        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end

        assert_equal 2, team_role_assignments.size

        actor_role_assignment = team_role_assignments.find { |a| a.actor.name == child_team.name }
        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        assert role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal parent_team.name, indirect_assignment.team_name
      end

      test "excludes as indirect source any ancestors of the directly assigned team" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")

        # parent team directly assigned role
        # child team inherits role from parent team
        # grandparent team is not assigned the role
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!

        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end

        assert_equal 2, team_role_assignments.size

        actor_role_assignment = team_role_assignments.find { |a| a.actor.name == child_team.name }
        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        refute_equal grandparent_team.name, indirect_assignment.team_name
        assert_equal parent_team.name, indirect_assignment.team_name
      end

      test "supports when the directly assigned team follows the indirectly assigned team" do
        # renaming teams to test when the child team is evaluated before the parent
        parent_team = create(:public_team, organization: @org, name: "AA Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "ZZ Child Team")
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!

        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end

        assert_equal 2, team_role_assignments.size

        actor_role_assignment = team_role_assignments.find { |a| a.actor.name == child_team.name }
        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.display_name, role_assignment.role.name

        assert_equal 1, role_assignment.indirect_assignments.size
        indirect_assignment = T.must(role_assignment.indirect_assignments.first)
        assert_equal parent_team.name, indirect_assignment.team_name
      end

      test "does not execute extra queries when indirect assignment sources are on a different page" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")
        teams = [grandparent_team, parent_team, child_team]
        teams.each do |team|
          Permissions::Granters::RoleGranter.new(actor: team, target: @org, role: @org_role).grant!
        end

        first_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
        second_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
        third_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
        fourth_page = T.let([], T::Array[RoleAssignments::Types::ActorRoleAssignment])
        RoleAssignments::FetchRoleAssignments.stub_const(:PAGE_SIZE, 1) do
          expected_query_count = TestEnv.test_all_features? ? 8 : 7
          assert_query_count(expected_query_count + 1, ignore_feature_flags: true) do
            # child team issues additional query for indirect assignments
            first_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
          end
          assert_query_count(expected_query_count, ignore_feature_flags: true) do
            # grandparent team has no indirect assignments to query
            second_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 2)
          end
          assert_query_count(expected_query_count + 1, ignore_feature_flags: true) do
            # parent team issues additional query for indirect assignments
            third_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 3)
          end
          assert_query_count(expected_query_count, ignore_feature_flags: true) do
            # empty page has no indirect assignments to query
            fourth_page = RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 4)
          end
        end

        assert_equal 1, first_page.size
        assert_equal 1, second_page.size
        assert_equal 1, third_page.size
        assert_equal 0, fourth_page.size

        sorted_names = teams.map(&:name).sort
        assert_same_elements sorted_names[...1], first_page.map { |assignment| assignment.actor.name }
        assert_same_elements sorted_names[1...2], second_page.map { |assignment| assignment.actor.name }
        assert_same_elements sorted_names[2..], third_page.map { |assignment| assignment.actor.name }
      end

      test "does not duplicate indirect sources when role is assigned to descendant teams" do
        grandparent_team = create(:public_team, organization: @org, name: "Grandparent Team", description: "Grandparent Team")
        parent_team = create(:public_team, organization: @org, parent_team: grandparent_team, name: "Parent Team", description: "Parent Team")
        child_team = create(:public_team, organization: @org, parent_team: parent_team, name: "Child Team", description: "Child Team")

        Permissions::Granters::RoleGranter.new(actor: grandparent_team, target: @org, role: @org_role).grant!
        Permissions::Granters::RoleGranter.new(actor: parent_team, target: @org, role: @org_role).grant!

        expected_query_count = TestEnv.test_all_features? ? 9 : 8
        team_role_assignments = assert_query_count(expected_query_count, ignore_feature_flags: true) do
          RoleAssignments::FetchRoleAssignments.new(target: @org).paginate_team_role_assignments(page: 1)
        end

        assert_equal 3, team_role_assignments.size
        actor_role_assignment = team_role_assignments.find { |a| a.actor.name == child_team.name }
        assert_equal child_team.name, actor_role_assignment.actor.name

        role_assignment = T.must(actor_role_assignment.role_assignments.first)
        refute role_assignment.directly_assigned
        assert_equal @org_role.name, role_assignment.role.name

        assert_equal 2, role_assignment.indirect_assignments.size
        assert_same_elements [grandparent_team.name, parent_team.name], role_assignment.indirect_assignments.map(&:team_name)
      end
    end
  end

  context "#directly_assigned_user_roles returns special role types" do
    test "includes enterprise-owned org roles" do
      enable_feature_flag(:enterprise_custom_organization_roles)
      enterprise_owned_org_role = OrganizationRole.create!(name: "Enterprise Owned Org Role", owner: @business, owner_type: "Business", description: "Desc")
      Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: enterprise_owned_org_role).grant!

      expected_count = GitHub.enterprise? ? 5 : 4
      role_assignments = assert_query_count(expected_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).send(:directly_assigned_user_roles)
      end

      user_role = role_assignments["User"].first
      assert_equal "User", user_role.actor_type
      assert_equal @user.id, user_role.actor_id
      assert_equal enterprise_owned_org_role.id, user_role.role_id
    end

    test "includes all-repo roles" do
      role = OrganizationRole.all_repo_triage_role
      Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: role).grant!

      expected_count = (GitHub.enterprise? || TestEnv.test_all_features?) ? 4 : 3
      role_assignments = assert_query_count(expected_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).send(:directly_assigned_user_roles)
      end

      user_role = role_assignments["User"].first
      assert_equal "User", user_role.actor_type
      assert_equal @user.id, user_role.actor_id
      assert_equal role.id, user_role.role_id
    end

    test "includes org security manager role" do
      security_manager_role = Role.security_manager_role
      Permissions::Granters::RoleGranter.new(actor: @user, target: @org, role: security_manager_role).grant!

      expected_count = (GitHub.enterprise? || TestEnv.test_all_features?) ? 4 : 3
      role_assignments = assert_query_count(expected_count, ignore_feature_flags: true) do
        RoleAssignments::FetchRoleAssignments.new(target: @org).send(:directly_assigned_user_roles)
      end

      user_role = role_assignments["User"].first
      assert_equal "User", user_role.actor_type
      assert_equal @user.id, user_role.actor_id
      assert_equal security_manager_role.id, user_role.role_id
    end
  end
end
