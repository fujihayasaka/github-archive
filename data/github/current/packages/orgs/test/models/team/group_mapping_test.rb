# typed: true
# frozen_string_literal: true

require "test_helper"

class TeamGroupMappingTest < GitHub::TestCase
  include HydroTestHelpers

  fixtures do
    @tenant = create :team_sync_tenant
    @org = @tenant.organization
    @owner = @org.admins.first
    @team = create(:team, organization: @org)

    @mapping_input1 = {
      group_id: "407d3e37-cac3-4aaa-80f7-c7e7f5b7c6fc",
      group_name: "saml-azuread-test",
      group_description: "just a test group",
    }
    @mapping_input2 = {
      group_id: "244145f2-c20f-43ae-bc6a-ffcd0ec0ccef",
      group_name: "saml-azuread-test-team-sync",
      group_description: "just another test group",
    }

    @mappings = [
      @mapping_input1,
      @mapping_input2,
    ]
  end

  def serializer
    Hydro::EntitySerializer
  end

  test "sets tenant from the team if it's missing" do
    mapping = build(:team_group_mapping, team: @team, tenant: nil)
    assert_nil mapping.tenant
    mapping.validate
    assert_equal @tenant, mapping.tenant
    assert_predicate mapping, :valid?, mapping.errors
  end

  context "audit logging" do
    test "adds event on create" do
      events = subscribe "team_group_mapping.create"
      expected_payload = {
        group_name: @mapping_input1[:group_name],
        team: @team.to_s,
        team_id: @team.id,
        org: @team.organization.to_s,
        org_id: @team.organization.id,
        actor: @owner.to_s,
        actor_id: @owner.id,
      }
      @team.group_mappings.create!(@mapping_input1.merge(actor: @owner))
      assert event = events.pop, "an event was expected"

      assert_equal event.payload, expected_payload
    end

    test "adds event on update" do
      events = subscribe "team_group_mapping.update"
      expected_payload = {
        team: @team.to_s,
        team_id: @team.id,
        org: @team.organization.to_s,
        org_id: @team.organization.id,
        actor: @owner.to_s,
        actor_id: @owner.id,
      }
      Team::GroupMapping.batch_update_mappings(@team, [@mapping_input1], actor: @owner)
      assert event = events.pop, "an event was expected"

      assert_equal event.payload, expected_payload
    end

    test "adds event on deletion" do
      mapping = @team.group_mappings.create!(@mapping_input1)
      events = subscribe "team_group_mapping.destroy"
      expected_payload = {
        group_name: @mapping_input1[:group_name],
        team: @team.to_s,
        team_id: @team.id,
        org: @team.organization.to_s,
        org_id: @team.organization.id,
        actor: @owner.to_s,
        actor_id: @owner.id,
      }

      mapping.actor = @owner
      mapping.destroy
      assert event = events.pop, "an event was expected"
      assert_equal event.payload, expected_payload
    end

    test "always instrument deletion including when the team has been destroyed" do
      mapping = @team.group_mappings.create!(@mapping_input1)
      @team.destroy
      mapping.reload
      events = subscribe "team_group_mapping.destroy"
      expected_payload = {
        group_name: @mapping_input1[:group_name],
        team: nil,
        team_id: @team.id,
        org: nil,
        actor: @owner.to_s,
        actor_id: @owner.id,
      }

      mapping.actor = @owner
      mapping.destroy
      assert event = events.pop, "an event was expected"
      assert_equal expected_payload, event.payload
    end
  end

  context "instrumentation emits event to GlobalInstrumenter" do
    test "when creating new mappings" do
      GlobalInstrumenter.expects(:instrument).with(
        "team_group_mapping.update",
        has_entries(
          team: anything,
          organization: anything,
          team_sync_tenant: anything,
          current_mappings: anything,
          previous_group_ids: [],
        ),
      )
      Team::GroupMapping.batch_update_mappings(@team, [@mapping_input1], actor: @owner)
    end

    test "when updating existing mappings" do
      @team.group_mappings.create!(@mapping_input1)

      GlobalInstrumenter.expects(:instrument).with(
        "team_group_mapping.update",
        has_entries(
          team: anything,
          organization: anything,
          team_sync_tenant: anything,
          current_mappings: anything,
          previous_group_ids: [@mapping_input1[:group_id]],
        ),
      )
      Team::GroupMapping.batch_update_mappings(@team, [@mapping_input2], actor: @owner)
    end

    test "when removing all mappings" do
      @team.group_mappings.create!(@mapping_input1)
      @team.group_mappings.create!(@mapping_input2)

      GlobalInstrumenter.expects(:instrument).with(
        "team_group_mapping.update",
        has_entries(
          team: anything,
          organization: anything,
          team_sync_tenant: anything,
          current_mappings: anything,
          previous_group_ids: includes(@mapping_input1[:group_id], @mapping_input2[:group_id]),
        ),
      )
      Team::GroupMapping.batch_update_mappings(@team, [], actor: @owner)
    end

    test "but not when nothing changes" do
      @team.group_mappings.create!(@mapping_input1)
      @team.group_mappings.create!(@mapping_input2)

      GlobalInstrumenter.expects(:instrument).with(
        "team_group_mapping.update",
        anything,
      ).never
      Team::GroupMapping.batch_update_mappings(@team, [@mapping_input1, @mapping_input2], actor: @owner)
    end
  end

  context "hydro events are published" do
    test "when creating new mappings" do
      mappings = Team::GroupMapping.batch_update_mappings(@team, [@mapping_input1], actor: @owner)
      assert_hydro_published({
        actor: serializer.user(@owner),
        team: serializer.team(@team),
        team_sync_tenant: serializer.team_sync_tenant(@tenant),
        organization: serializer.organization(@tenant.organization),
        current_mappings: mappings.map { |mapping| serializer.team_group_mapping(mapping) },
        previous_group_ids: [],
      }, schema: "github.v1.TeamGroupMappingUpdate")
    end

    test "when updating existing mappings" do
      @team.group_mappings.create!(@mapping_input1)
      mappings = Team::GroupMapping.batch_update_mappings(@team, [@mapping_input2], actor: @owner)

      assert_hydro_published({
        actor: serializer.user(@owner),
        team: serializer.team(@team),
        team_sync_tenant: serializer.team_sync_tenant(@tenant),
        organization: serializer.organization(@tenant.organization),
        current_mappings: mappings.map { |mapping| serializer.team_group_mapping(mapping) },
        previous_group_ids: [@mapping_input1[:group_id]],
      }, schema: "github.v1.TeamGroupMappingUpdate")
    end

    test "when removing all mappings" do
      @team.group_mappings.create!(@mapping_input1)
      Team::GroupMapping.batch_update_mappings(@team, [], actor: @owner)

      assert_hydro_published({
        actor: serializer.user(@owner),
        team: serializer.team(@team),
        team_sync_tenant: serializer.team_sync_tenant(@tenant),
        organization: serializer.organization(@tenant.organization),
        current_mappings: [],
        previous_group_ids: [@mapping_input1[:group_id]],
      }, schema: "github.v1.TeamGroupMappingUpdate")
    end

    test "but not when nothing changes" do
      @team.group_mappings.create!(@mapping_input1)
      @team.group_mappings.create!(@mapping_input2)
      Team::GroupMapping.batch_update_mappings(@team, [@mapping_input1, @mapping_input2], actor: @owner)
      refute_hydro_messages(schema: "github.v1.TeamGroupMappingUpdate")
    end
  end
end if GitHub.team_synchronization_available?
