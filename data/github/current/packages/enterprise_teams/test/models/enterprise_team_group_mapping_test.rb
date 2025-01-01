# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamGroupMappingTest < GitHub::TestCase
  include AuthenticationHelpers::SAML
  fixtures do
    if GitHub.single_business_environment?
      setup_saml_auth_mode(with_scim: true)
      @business = create :global_business
      @provider = create :business_saml_provider, business: @business
      @provider.update(scim_provisioning_state: "scim_provisioning_state_enabled")
      @owner = @business.owners.first
    else
      @owner = create :emu, :owner
      @business = @owner.enterprise_managed_business
    end

    @enterprise_team = create :enterprise_team, business: @business
    @external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
    @enterprise_team_group_mapping = EnterpriseTeamGroupMapping.create!(enterprise_team: @enterprise_team, external_group: @external_group)
    @team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
  end

  setup do
    if GitHub.single_business_environment?
      GitHub.stubs(:esm_enabled?).returns(true)
      setup_saml_auth_mode(with_scim: true)
    end
  end

  test "validates presence of enterprise_team_id" do
    @enterprise_team_group_mapping.enterprise_team_id = nil
    refute_predicate @enterprise_team_group_mapping, :valid?
  end

  test "validates presence of external_group_id" do
    @enterprise_team_group_mapping.external_group_id = nil
    refute_predicate @enterprise_team_group_mapping, :valid?
  end

  test "belongs to enterprise_team" do
    assert_equal @enterprise_team, @enterprise_team_group_mapping.enterprise_team
  end

  test "belongs to external_group" do
    assert_equal @external_group, @enterprise_team_group_mapping.external_group
  end

  test "returns active mappings" do
    assert_includes EnterpriseTeamGroupMapping.active, @enterprise_team_group_mapping
    @enterprise_team_group_mapping.update(deleted_at: Time.now)
    refute_includes EnterpriseTeamGroupMapping.active, @enterprise_team_group_mapping
  end

  test "returns deleted mappings" do
    @enterprise_team_group_mapping.update(deleted_at: Time.now)
    assert_includes EnterpriseTeamGroupMapping.deleted, @enterprise_team_group_mapping
  end

  test "enforces uniqueness on enterprise team and external group pairings" do
    assert_raises ActiveRecord::RecordInvalid do
      EnterpriseTeamGroupMapping.create!(enterprise_team: @enterprise_team, external_group: @external_group)
    end
  end

  test "allows multiple mappings of different external groups within a business" do
    EnterpriseTeamGroupMapping.create!(
      enterprise_team: @enterprise_team,
      external_group: create(:external_group)
    )

    assert_equal 2, EnterpriseTeamGroupMapping.where(enterprise_team: @enterprise_team).count
  end

  context "enterprise_team.copilot.update events" do
    test "does not emit enterprise_team.copilot.update event when team is not a copilot team" do
      team = create :enterprise_team, business: @business, name: "test123"
      external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 3)
      events = subscribe("enterprise_team.copilot.update")
      team.enterprise_team_group_mappings.create!(external_group: external_group)

      event = events.pop
      assert_nil event
    end

    test "does not emit enterprise_team.copilot.update event when the team is a copilot team and only name is changed" do
      events = subscribe("enterprise_team.copilot.update")
      @enterprise_team.update(name: "copilot001")

      event = events.pop
      assert_nil event
    end

    test "emits enterprise_team.copilot.update event when the team is a copilot team and IDP group is added" do
      @enterprise_team_group_mapping.destroy!
      events = subscribe("enterprise_team.copilot.update")
      EnterpriseTeamGroupMapping.create!(enterprise_team: @enterprise_team, external_group: @external_group)
      expected_payload = {
        id: @enterprise_team.id,
      }

      assert_equal 1, events.size
      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "emits enterprise_team.copilot.update event when the team is a copilot team and IDP group is changed" do
      events = subscribe("enterprise_team.copilot.update")
      new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)
      @enterprise_team_group_mapping.update(external_group: new_external_group)
      expected_payload = {
        id: @enterprise_team.id,
      }

      assert_equal 1, events.size
      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end

    test "emits enterprise_team.copilot.update event when the team is a copilot team and IDP group is unassigned" do
      events = subscribe("enterprise_team.copilot.update")
      @enterprise_team_group_mapping.update(deleted_at: Time.now)
      team_mappings = @enterprise_team.enterprise_team_group_mappings
      expected_payload = {
        id: @enterprise_team.id,
      }

      assert_equal 1, events.size
      event = events.pop
      refute_nil event
      assert_equal 0, team_mappings.count
      assert_equal "enterprise_team.copilot.update", event.name
      assert_equal expected_payload, event.payload
    end
  end unless GitHub.single_business_environment?  # Enterprise teams not used for Copilot in GHES

  context "#instrument enterprise_team.add_member" do

    test "emits event when IdP group is assigned" do
      @enterprise_team_group_mapping.destroy!
      events = subscribe("enterprise_team.add_member")
      EnterpriseTeamGroupMapping.create!(enterprise_team: @enterprise_team, external_group: @external_group)

      external_identity_1 = @external_group.members.first.external_identity
      external_identity_2 = @external_group.members.second.external_identity

      expected_payload = [{
        user_id: external_identity_1.user_id,
        user: external_identity_1.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }, {
        user_id: external_identity_2.user_id,
        user: external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      assert_equal "enterprise_team.add_member", events.first.name
      event_payloads = [events.pop.payload, events.pop.payload]
      assert_same_elements expected_payload, event_payloads
    end

    test "emits event when we switch to a diff IdP group" do
      new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)

      # have first user be part of both groups, so events are not emitted for them
      ExternalIdentityGroupMembership.create(external_group: new_external_group, external_identity: @external_group.members.first.external_identity)

      remove_events = subscribe("enterprise_team.remove_member")
      add_events = subscribe("enterprise_team.add_member")
      @enterprise_team_group_mapping.update!(external_group: new_external_group)

      old_external_identity_2 = @external_group.members.second.external_identity

      expected_remove_payload = [{
        user_id: old_external_identity_2.user_id,
        user: old_external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      assert_equal 1, remove_events.size
      assert_equal "enterprise_team.remove_member", remove_events.first.name
      remove_event_payloads = [remove_events.pop.payload]
      assert_same_elements expected_remove_payload, remove_event_payloads

      new_external_identity_1 = new_external_group.members.first.external_identity
      new_external_identity_2 = new_external_group.members.second.external_identity

      expected_add_payload = [{
        user_id: new_external_identity_1.user_id,
        user: new_external_identity_1.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }, {
        user_id: new_external_identity_2.user_id,
        user: new_external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      assert_equal 2, add_events.size
      assert_equal "enterprise_team.add_member", add_events.first.name
      add_event_payloads = [add_events.pop.payload, add_events.pop.payload]
      assert_same_elements expected_add_payload, add_event_payloads
    end

    test "emits event when external_group.add_member is emitted" do
      user = create_user_with_ext_id
      external_identity = user.external_identities.first
      ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: external_identity)

      events = subscribe("enterprise_team.add_member")
      @external_group.instrument_event(:add_member, nil, user: user)

      expected_payload = {
        user_id: external_identity.user_id,
        user: external_identity.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.add_member", event.name
      assert_equal expected_payload, event.payload
    end
  end

  context "#instrument enterprise_team.remove_member" do

    test "emits event when IdP group is unassigned then reassigned" do
      external_identity_1 = @external_group.members.first.external_identity
      external_identity_2 = @external_group.members.second.external_identity

      expected_payload = [{
        user_id: external_identity_1.user_id,
        user: external_identity_1.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }, {
        user_id: external_identity_2.user_id,
        user: external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      events = subscribe("enterprise_team.remove_member")
      @enterprise_team_group_mapping.update(deleted_at: Time.now)

      refute_nil events.first
      assert_equal "enterprise_team.remove_member", events.first.name
      event_payloads = [events.pop.payload, events.pop.payload]
      assert_same_elements expected_payload, event_payloads

      # Reassigning must work and readd all members
      events = subscribe("enterprise_team.add_member")
      @enterprise_team_group_mapping.update(deleted_at: nil)

      refute_nil events.first
      assert_equal "enterprise_team.add_member", events.first.name
      event_payloads = [events.pop.payload, events.pop.payload]
      assert_same_elements expected_payload, event_payloads
    end

    test "emits event when IdP group is unassigned then reassigned to another group" do
      external_identity_1 = @external_group.members.first.external_identity
      external_identity_2 = @external_group.members.second.external_identity

      expected_payload = [{
        user_id: external_identity_1.user_id,
        user: external_identity_1.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }, {
        user_id: external_identity_2.user_id,
        user: external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      events = subscribe("enterprise_team.remove_member")
      @enterprise_team_group_mapping.update(deleted_at: Time.now)

      refute_nil events.first
      assert_equal "enterprise_team.remove_member", events.first.name
      event_payloads = [events.pop.payload, events.pop.payload]
      assert_same_elements expected_payload, event_payloads

      # Undo delete of the record and changing id at the same time must add new members and not emit remove members
      new_external_group = create(:external_group, :with_members, :with_team, business: @business, number_of_members: 2)

      external_identity_1 = new_external_group.members.first.external_identity
      external_identity_2 = new_external_group.members.second.external_identity

      expected_payload = [{
        user_id: external_identity_1.user_id,
        user: external_identity_1.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }, {
        user_id: external_identity_2.user_id,
        user: external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      remove_events = subscribe("enterprise_team.remove_member")
      add_events = subscribe("enterprise_team.add_member")
      @enterprise_team_group_mapping.update(external_group_id: new_external_group.id, deleted_at: nil)

      assert_nil remove_events.first

      refute_nil add_events.first
      assert_equal "enterprise_team.add_member", add_events.first.name
      event_payloads = [add_events.pop.payload, add_events.pop.payload]
      assert_same_elements expected_payload, event_payloads
    end

    test "emits event for when Idp group is deleted on the Idp side" do
      events = subscribe("enterprise_team.remove_member")
      ClearEnterpriseTeamGroupMappingsJob.perform_now(@external_group.id)

      external_identity_1 = @external_group.members.first.external_identity
      external_identity_2 = @external_group.members.second.external_identity

      expected_payload = [{
        user_id: external_identity_1.user_id,
        user: external_identity_1.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }, {
        user_id: external_identity_2.user_id,
        user: external_identity_2.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }]

      assert_equal 2, events.size
      assert_equal "enterprise_team.remove_member", events.first.name
      event_payloads = [events.pop.payload, events.pop.payload]
      assert_same_elements expected_payload, event_payloads
    end

    test "emits event when external_group.remove_member is emitted" do
      user = create_user_with_ext_id
      external_identity = user.external_identities.first
      ExternalIdentityGroupMembership.create(external_group: @external_group, external_identity: external_identity)

      events = subscribe("enterprise_team.remove_member")
      @external_group.instrument_event(:remove_member, nil, user: user)

      expected_payload = {
        user_id: external_identity.user_id,
        user: external_identity.user.login,
        business_id: @business.id,
        business: @business.slug,
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.name,
      }

      event = events.pop
      refute_nil event
      assert_equal "enterprise_team.remove_member", event.name
      assert_equal expected_payload, event.payload
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
