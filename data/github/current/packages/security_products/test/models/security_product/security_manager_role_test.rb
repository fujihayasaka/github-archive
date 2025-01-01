# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProduct
  class SecurityManagerRoleTest < GitHub::TestCase
    fixtures do
      @owner = create :user
      @org = create :organization, admin: @owner

      @user = create(:user)
      @security_manager_user = create(:user).tap do |user|
        SecurityCenter::FeatureFlagHelper.stubs(:show_security_manager_in_org_role_assignment?).returns(true)
        grant_security_manager_role user, organization: @org
        SecurityCenter::FeatureFlagHelper.unstub(:show_security_manager_in_org_role_assignment?)
      end

      # Team with 2 child teams. One with and one without the role.
      @team = create(:team, organization: @org, privacy: :closed).tap do |parent|
        @team_child = create :team, organization: @org, privacy: :closed, parent_team_id: parent.id

        @team_security_manager_child = create :team, organization: @org, privacy: :closed, parent_team_id: parent.id
        grant_security_manager_role @team_security_manager_child, organization: @org
      end

      # Security manager team with child team that hasn't been assigned the role
      @security_manager_team = create(:team, organization: @org, privacy: :closed).tap do |parent|
        grant_security_manager_role parent, organization: @org
        @security_manager_team_child = create :team, organization: @org, privacy: :closed, parent_team_id: parent.id
      end
    end

    context "#new" do
      test "raises error if called" do
        assert_raises(NoMethodError) { SecurityManagerRole.new }
      end
    end

    context ".granted?" do
      test "raises error if called with invalid actor" do
        assert_raises(ArgumentError) { SecurityManagerRole.granted? @org, target: @org } # org is not a vanilla user
      end

      test "returns true if actor has role for the given target" do
        assert SecurityManagerRole.granted? @security_manager_user, target: @org
        assert SecurityManagerRole.granted? @security_manager_team, target: @org
        assert SecurityManagerRole.granted? @team_security_manager_child, target: @org
      end

      test "returns false if actor does not have role for the given target" do
        refute SecurityManagerRole.granted? @user, target: @org
        refute SecurityManagerRole.granted? @team, target: @org
        refute SecurityManagerRole.granted? @team_child, target: @org
        refute SecurityManagerRole.granted? @security_manager_team_child, target: @org

        # The role is granted in a different target
        wrong_target = create :organization
        refute SecurityManagerRole.granted? @security_manager_user, target: wrong_target
        refute SecurityManagerRole.granted? @security_manager_team, target: wrong_target
      end
    end

    context ".granted_to_team?" do
      test "returns true if .granted? returns true" do
        SecurityManagerRole.expects(:granted?).with(@team, target: @team.organization).returns(true)
        assert SecurityManagerRole.granted_to_team? @team
      end

      test "returns false if .granted? returns false" do
        SecurityManagerRole.expects(:granted?).with(@security_manager_team, target: @security_manager_team.organization).returns(false)
        refute SecurityManagerRole.granted_to_team? @security_manager_team
      end
    end

    context ".filter_granted" do
      test "raises error if called without array of teams" do
        assert_raises(ArgumentError) { SecurityManagerRole.filter_granted [@security_manager_team, @org] }
      end

      test "returns array with team if called with one team" do
        assert_same_elements [@security_manager_team], SecurityManagerRole.filter_granted(@security_manager_team)
      end

      test "returns array of teams that have role if called with array of teams" do
        assert_same_elements [@security_manager_team, @team_security_manager_child], SecurityManagerRole.filter_granted([@team, @team_child, @team_security_manager_child, @security_manager_team, @security_manager_team_child])
      end

      test "returns empty array if no teams have role" do
        assert_equal [], SecurityManagerRole.filter_granted([@team])
      end
    end

    context ".granted_to_team_or_inherited?" do
      test "returns true if team has role" do
        assert SecurityManagerRole.granted_to_team_or_inherited?(@security_manager_team)
        assert SecurityManagerRole.granted_to_team_or_inherited?(@team_security_manager_child)
      end

      test "returns true if a parent team has role" do
        assert SecurityManagerRole.granted_to_team_or_inherited?(@security_manager_team_child)
      end

      test "returns false if neither the team nor its parents have the role" do
        refute SecurityManagerRole.granted_to_team_or_inherited?(@team)
        refute SecurityManagerRole.granted_to_team_or_inherited?(@team_child)
      end
    end

    context ".grant_to_team!" do
      test "grants the security manager role to a team and instruments the grant" do
        events = subscribe "org.add_security_manager"
        team = create :team, organization: create(:organization, admin: @owner)
        refute SecurityManagerRole.granted_to_team?(team)

        SecurityManagerRole.grant_to_team!(team)

        assert SecurityManagerRole.granted_to_team?(team)
        assert event = events.pop, "an event was expected"

        expected_payload = {
          org: team.organization.login,
          org_id: team.organization.id,
          team: team.combined_slug,
          team_id: team.id,
        }
        assert_equal expected_payload, event.payload
      end

      test "no-ops if the team already has the role" do
        team = create :team, organization: create(:organization, admin: @owner)
        grant_security_manager_role team, organization: team.organization
        assert SecurityManagerRole.granted_to_team?(team)

        SecurityManagerRole.grant_to_team!(team)

        assert SecurityManagerRole.granted_to_team?(team)
      end
    end

    context ".revoke_from_team!" do
      test "raises error if team was enterprise-team-synced Security Managers", skip_enterprise: true do
        EnterpriseTeam.expects(:enabled_for_organizations?).at_least_once.returns(true)

        team = create :team, organization: @org
        @org.business = create(:business)
        @org.save!
        enterprise_team = create :enterprise_team, business: @org.business, sync_to_organizations: "all"
        EnterpriseTeamOrganizationMapping.create(enterprise_team: enterprise_team, organization: @org, team: team)

        assert_predicate team, :enterprise_team_managed?

        grant_security_manager_role team, organization: team.organization
        assert SecurityManagerRole.granted_to_team?(team)

        assert_raises ArgumentError do
          SecurityManagerRole.revoke_from_team!(team)
        end

        SecurityManagerRole.revoke_from_team!(team, caller: :enterprise_team)
        refute SecurityManagerRole.granted_to_team?(team)
      end

      test "revokes the Security Manager role from a team and instruments the revocation" do
        events = subscribe "org.remove_security_manager"

        # We don't use `create :security_manager_team`
        # because otherwise we'd be using this class under test to grant the role.
        team = create :team, organization: create(:organization, admin: @owner)
        grant_security_manager_role team, organization: team.organization
        assert SecurityManagerRole.granted_to_team?(team)

        SecurityManagerRole.revoke_from_team!(team)

        refute SecurityManagerRole.granted_to_team?(team)

        assert event = events.pop, "an event was expected"

        expected_payload = {
          org: team.organization.login,
          org_id: team.organization.id,
          team: team.combined_slug,
          team_id: team.id,
        }
        assert_equal expected_payload, event.payload
      end

      test "no-ops if the team didn't already have the role" do
        team = create :team, organization: create(:organization, admin: @owner)
        refute SecurityManagerRole.granted_to_team?(team)

        SecurityManagerRole.revoke_from_team!(team)

        refute SecurityManagerRole.granted_to_team?(team)
      end
    end

    def grant_security_manager_role(actor, organization:)
      # We use the role granter directly instead of `SecurityManagerRole.grant!`
      # because otherwise we'd be using this class under test for grant/revoke testing.
      ::Permissions::Granters::RoleGranter.new(
        actor:,
        role: Role.security_manager_role,
        target: organization,
      ).grant!
    end
  end
end
