# typed: true
# frozen_string_literal: true

require "test_helper"

module SecurityProduct
  class EnterpriseSecurityManagerRoleTest < GitHub::TestCase
    fixtures do
      @owner = create :user
      @business = create :business, owners: [@owner]

      @team = create(:enterprise_team, business: @business)

      @security_manager_team = create(:enterprise_security_manager_team, business: @business)
    end

    context "new" do
      test "raises error if called" do
        assert_raises(NoMethodError) { EnterpriseSecurityManagerRole.new }
      end
    end

    context ".granted?" do
      test "returns true if team has role" do
        assert EnterpriseSecurityManagerRole.granted? @security_manager_team
      end

      test "returns false if team does not have role" do
        refute EnterpriseSecurityManagerRole.granted? @team
      end
    end

    context ".grant!" do
      test "grants the security manager role to a team" do
        events = subscribe "business.add_security_manager"

        team = create :enterprise_team, business: @business
        refute EnterpriseSecurityManagerRole.granted?(team)

        EnterpriseSecurityManagerRole.grant!(team)

        assert EnterpriseSecurityManagerRole.granted?(team)

        assert event = events.pop, "an event was expected"
        assert_equal "business.add_security_manager", event.name
        assert_equal({
          business: @business.slug,
          business_id: @business.id,
          enterprise_team: team.slug,
          enterprise_team_id: team.id,
        }, event.payload)
      end

      test "no-ops if the team already has the role" do
        events = subscribe "business.add_security_manager"

        team = create :enterprise_team, business: @business
        grant_enterprise_security_manager_role team
        assert EnterpriseSecurityManagerRole.granted?(team)

        EnterpriseSecurityManagerRole.grant!(team)

        assert EnterpriseSecurityManagerRole.granted?(team)
        assert_empty events
      end
    end

    context ".revoke!" do
      test "revokes the Security Manager role from a team and instruments the revocation" do
        events = subscribe "business.remove_security_manager"

        team = create :enterprise_team, business: @business
        grant_enterprise_security_manager_role team
        assert EnterpriseSecurityManagerRole.granted?(team)

        EnterpriseSecurityManagerRole.revoke!(team)

        refute EnterpriseSecurityManagerRole.granted?(team)
        assert event = events.pop, "an event was expected"
        assert_equal "business.remove_security_manager", event.name
        assert_equal({
          business: @business.slug,
          business_id: @business.id,
          enterprise_team: team.slug,
          enterprise_team_id: team.id,
        }, event.payload)
      end

      test "no-ops if the team didn't already have the role" do
        events = subscribe "business.remove_security_manager"

        team = create :enterprise_team, business: @business
        refute EnterpriseSecurityManagerRole.granted?(team)

        EnterpriseSecurityManagerRole.revoke!(team)

        refute EnterpriseSecurityManagerRole.granted?(team)
        assert_empty events
      end
    end

    def grant_enterprise_security_manager_role(team)
      # We use the role granter directly instead of `SecurityManagerRole.grant!`
      # because otherwise we'd be using this class under test for grant/revoke testing.
      ::Permissions::Granters::RoleGranter.new(
        actor: team,
        role: Role.enterprise_security_manager_role,
        target: team.business
      ).grant!
    end
  end
end
