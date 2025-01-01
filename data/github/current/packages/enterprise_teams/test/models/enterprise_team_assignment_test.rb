# typed: true
# frozen_string_literal: true

require "test_helper"

class EnterpriseTeamAssignmentTest < GitHub::TestCase
  setup do
    @business = create :business
    @enterprise_team = create :enterprise_team, business: @business
    @enterprise_team_assignment = EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
  end

  test "validates presence of enterprise_team_id" do
    @enterprise_team_assignment.enterprise_team_id = nil
    refute_predicate @enterprise_team_assignment, :valid?
  end

  test "validates presence of assignment_type" do
    @enterprise_team_assignment.assignment_type = ""
    refute_predicate @enterprise_team_assignment, :valid?
  end

  test "validates format of assignment_type" do
    @enterprise_team_assignment.assignment_type = :custom_type
    refute_predicate @enterprise_team_assignment, :valid?
  end

  test "belongs to enterprise_team" do
    assert_equal @enterprise_team, @enterprise_team_assignment.enterprise_team
  end

  test "enforces uniqueness on enterprise team and assignment pairings" do
    assert_raises ActiveRecord::RecordInvalid do
      EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: :copilot)
    end
  end

  context "#instrument" do

    test "emits assignment event with audit log" do
      enterprise_team = create :enterprise_team, business: @business
      new_events = subscribe("enterprise_team.copilot_assignment")
      old_events = subscribe("enterprise_team.copilot.assignment")

      EnterpriseTeamAssignment.create!(enterprise_team: enterprise_team, assignment_type: :copilot)

      expected_payload = {
        enterprise_team_id: enterprise_team.id,
        enterprise_team: enterprise_team.slug,
        business: @business.name,
        business_id: @business.id,
      }

      event = new_events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot_assignment", event.name
      assert_equal expected_payload, event.payload

      expected_payload = {
        id: enterprise_team.id
      }

      event = old_events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.assignment", event.name
      assert_equal expected_payload, event.payload
    end

    test "does not emits assignment event on create if skip_event_emissions is true" do
      enterprise_team = create :enterprise_team, business: @business
      new_events = subscribe("enterprise_team.copilot_assignment")
      old_events = subscribe("enterprise_team.copilot.assignment")

      assignment = EnterpriseTeamAssignment.new(enterprise_team: enterprise_team, assignment_type: :copilot)
      assignment.skip_event_emissions = true
      assignment.save!

      assert_nil new_events.pop
      assert_nil old_events.pop
    end

    test "emits unassignment event when destroyed with audit log" do
      new_events = subscribe("enterprise_team.copilot_unassignment")
      old_events = subscribe("enterprise_team.copilot.unassignment")

      id = @enterprise_team.id
      slug = @enterprise_team.slug

      @enterprise_team_assignment.destroy

      expected_payload = {
        enterprise_team_id: @enterprise_team.id,
        enterprise_team: @enterprise_team.slug,
        business: @business.name,
        business_id: @business.id,
      }

      event = new_events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot_unassignment", event.name
      assert_equal expected_payload, event.payload

      expected_payload = {
        id: @enterprise_team.id
      }

      event = old_events.pop
      refute_nil event
      assert_equal "enterprise_team.copilot.unassignment", event.name
      assert_equal expected_payload, event.payload
    end

    test "does not emits unassignment event on destroy if skip_event_emissions is true" do
      new_events = subscribe("enterprise_team.copilot_unassignment")
      old_events = subscribe("enterprise_team.copilot.unassignment")

      @enterprise_team_assignment.skip_event_emissions = true
      @enterprise_team_assignment.destroy!

      assert_nil new_events.pop
      assert_nil old_events.pop
    end
  end
end
