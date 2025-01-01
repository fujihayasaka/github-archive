# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProduct
  class SecurityManagersTest < GitHub::TestCase
    fixtures do
      @owner = create(:user)

      @org = create(:organization, admin: @owner)
      @empty_org = create(:organization, admin: @owner)

      @member = create(:user)
      @org.add_member(@member)

      create(:team, organization: @org)
      @security_manager_team_1 = create(:security_manager_team, organization: @org, privacy: :closed)
      @security_manager_team_2 = create(:security_manager_team, organization: @org, privacy: :closed)
      @security_manager_team_3 = create(:security_manager_team, organization: @org, privacy: :closed)
      @security_manager_team_4 = create(:security_manager_team, organization: @org, privacy: :closed)
      @security_manager_team_5 = create(:security_manager_team, organization: @org, privacy: :closed)
      @security_manager_team_6 = create(:security_manager_team, organization: @org, privacy: :closed)

      @directly_assigned_security_manager = create(:user)
      @org.add_member(@directly_assigned_security_manager)
      @org.grant_org_role(assignee: @directly_assigned_security_manager, role: Role.security_manager_role)

      create(:team, organization: @org, parent_team_id: @security_manager_team_1.id, privacy: :closed)
      @secret_security_manager_team = create(:security_manager_team, organization: @org)

      @all_security_manager_teams = [
        @security_manager_team_1,
        @security_manager_team_2,
        @security_manager_team_3,
        @security_manager_team_4,
        @security_manager_team_5,
        @security_manager_team_6,
        @secret_security_manager_team,
      ]
    end

    context "new" do
      test "raises error if passed arg isn't an org" do
        assert_raises(ArgumentError) { SecurityManagers.new(nil) }
        assert_raises(ArgumentError) { SecurityManagers.new(@owner) }
        assert_raises(ArgumentError) { SecurityManagers.new(1) }

        assert SecurityManagers.new(@org) # passing an org doesn't raise an error
      end
    end

    context "team_ids" do
      test "returns empty array for orgs without any security managers" do
        assert_same_elements [], SecurityManagers.new(@empty_org).team_ids
      end

      test "returns the IDs of teams granted the security manager role" do
        assert_same_elements \
          @all_security_manager_teams.map(&:id),
          SecurityManagers.new(@org).team_ids
      end
    end

    context "teams" do
      test "returns empty array for orgs without any security managers" do
        assert_same_elements [], SecurityManagers.new(@empty_org).teams
      end

      test "returns teams granted the security manager role" do
        assert_same_elements @all_security_manager_teams, SecurityManagers.new(@org).teams
      end
    end

    context "teams_visible_to" do
      test "returns only teams visible to the user" do
        assert_same_elements \
          @all_security_manager_teams,
          SecurityManagers.new(@org).teams_visible_to(@owner)

        assert_same_elements \
          @all_security_manager_teams - [@secret_security_manager_team],
          SecurityManagers.new(@org).teams_visible_to(@member)
      end
    end

    context "directly_assigned_user_ids" do
      test "returns empty array for orgs without any security manager users" do
        assert_same_elements [], SecurityManagers.new(@empty_org).directly_assigned_user_ids
      end

      test "returns the IDs of users granted the security manager role directly" do
        assert_same_elements \
          [@directly_assigned_security_manager.id],
          SecurityManagers.new(@org).directly_assigned_user_ids
      end
    end
  end
end
