# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamMembershipTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @business = create :global_business
      @provider = create :business_saml_provider, business: @business
      @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
      @user = @business.owners.first
    else
      @user = create :emu
      @business = @user.enterprise_managed_business
    end
    @enterprise_team = create :enterprise_team, business: @business
    @enterprise_team_membership = EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team, user: @user)
  end

  setup do
    if GitHub.single_business_environment?
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
    end
  end

  test "validates presence of enterprise_team_id" do
    @enterprise_team_membership.enterprise_team_id = nil
    refute_predicate @enterprise_team_membership, :valid?
  end

  test "validates presence of user" do
    @enterprise_team_membership.user = nil
    refute_predicate @enterprise_team_membership, :valid?
  end

  test "belongs to enterprise_team" do
    assert_equal @enterprise_team, @enterprise_team_membership.enterprise_team
  end

  test "belongs to user" do
    assert_equal @user, @enterprise_team_membership.user
  end

  test "enforces uniqueness on enterprise team and user pairings" do
    assert_raises ActiveRecord::RecordInvalid do
      EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team, user: @user)
    end
  end

  test "allows multiple mappings of different users within a business" do
    EnterpriseTeamMembership.create!(
      enterprise_team: @enterprise_team,
      user: create(:user)
    )
    enterprise_team2 = create :enterprise_team, business: @business
    EnterpriseTeamMembership.create!(
      enterprise_team: enterprise_team2,
      user: create(:user)
    )

    assert_equal 2, EnterpriseTeamMembership.where(enterprise_team: @enterprise_team).count
    assert_equal 1, EnterpriseTeamMembership.where(enterprise_team: enterprise_team2).count
  end

  context "#instrument" do
    test "instrument update event on create" do
      events = subscribe("enterprise_team.copilot.update")

      EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
      EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team, user: create(:user))

      expected_payload = {
        id: @enterprise_team.id,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "don't instrument event on create when no copilot assignment" do
      events = subscribe("enterprise_team.copilot.update")

      EnterpriseTeamMembership.create!(enterprise_team: @enterprise_team, user: create(:user))

      event = events.pop
      assert_nil event
    end

    test "instrument update event on destroy" do
      events = subscribe("enterprise_team.copilot.update")

      EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
      @enterprise_team_membership.destroy

      expected_payload = {
        id: @enterprise_team.id,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "don't instrument update event on destroy when no copilot assignment" do
      events = subscribe("enterprise_team.copilot.update")

      @enterprise_team_membership.destroy

      event = events.pop
      assert_nil event
    end

    test "don't instrument update event on destroy team" do
      enterprise_team = create :enterprise_team, business: @business
      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)
      EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: create(:user))

      events = subscribe("enterprise_team.copilot.update")

      perform_enqueued_jobs only: DestroyDependentRecordsJob do
        enterprise_team.destroy
      end

      event = events.pop
      assert_nil event
    end

    test "don't instrument update event per member on switch to IDP" do
      enterprise_team = create :enterprise_team, business: @business
      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)
      EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: create(:user))
      EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: create(:user))

      external_group = create(:external_group, :with_members, business: @business, number_of_members: 3)
      EnterpriseTeamGroupMapping.create!(enterprise_team: enterprise_team, external_group: external_group)

      events = subscribe("enterprise_team.copilot.update")

      perform_enqueued_jobs only: ClearEnterpriseTeamMembershipsJob do
        ClearEnterpriseTeamMembershipsJob.enqueue(enterprise_team)
      end

      event = events.pop
      assert_nil event
    end
  end

  context "#instrument enterprise_team.remove_member" do

    test "instrument per member on switch to IdP" do
      enterprise_team = create :enterprise_team, business: @business
      user1 = create_user_with_ext_id
      user2 = create_user_with_ext_id
      EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: user1)
      EnterpriseTeamMembership.create!(enterprise_team: enterprise_team, user: user2)

      events = subscribe("enterprise_team.remove_member")

      expected_payload = [{
        user_id: user1.id,
        user: user1.display_login,
        business_id: enterprise_team.business.id,
        business: enterprise_team.business.slug,
        enterprise_team_id: enterprise_team.id,
        enterprise_team: enterprise_team.name,
      }, {
        user_id: user2.id,
        user: user2.display_login,
        business_id: enterprise_team.business.id,
        business: enterprise_team.business.slug,
        enterprise_team_id: enterprise_team.id,
        enterprise_team: enterprise_team.name,
      }]

      perform_enqueued_jobs only: ClearEnterpriseTeamMembershipsJob do
        ClearEnterpriseTeamMembershipsJob.enqueue(enterprise_team)
      end

      assert_equal events.count, 2
      assert_equal "enterprise_team.remove_member", events.first.name
      event_payloads = [events.pop.payload, events.pop.payload]
      assert_same_elements expected_payload, event_payloads
    end
  end

  private def create_user_with_ext_id
    if GitHub.single_business_environment?
      create :ghes_scim_user, business: @business
    else
      create :emu, business: @business
    end
  end
end
