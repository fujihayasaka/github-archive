# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::Payloads::Businesses::EnterpriseTeamSearchTest < GitHub::TestCase
  include GitHub::LoggerHelper
  include CopilotTestHelper # automatically disables Copilot feature flags

  fixtures do
    @business = T.let(create(:business, :enterprise_managed_business, seats_plan_type: :basic), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @enterprise_team = T.let(create(:copilot_enterprise_team, business: @business, name: "Awesome-Team"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @unassigned_team = create(:enterprise_team, business: @business, name: "Unassigned-Team")
    @enterprise_team_assignment = T.let(EnterpriseTeamAssignment.create!(enterprise_team: @enterprise_team, assignment_type: "copilot"), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
    @seat_assignment = T.let(create(:copilot_seat_assignment, :enterprise_team, assignable: @enterprise_team, owner: @business), T.untyped) # rubocop:todo Sorbet/ForbidTUntyped
  end

  def expected_payload
    {
      total: 2,
      teams: [{
        id: @seat_assignment.id,
        assignable_type: @seat_assignment.assignable_type,
        pending_cancellation_date: @seat_assignment.pending_cancellation_date,
        last_activity_at: nil,
        status: Copilot::Types::SeatAssignment::Status::Stable.serialize,
        assignable: {
          id: @enterprise_team.id,
          mapping_id: @enterprise_team.enterprise_team_group_mappings.first&.external_group&.id,
          slug: @enterprise_team.slug,
          login: @enterprise_team.name,
          member_count: @enterprise_team.member_count,
          member_ids: @enterprise_team.member_user_ids
        }
      }, {
        id: nil,
        assignable_type: "EnterpriseTeam",
        pending_cancellation_date: nil,
        last_activity_at: nil,
        status: Copilot::Types::SeatAssignment::Status::Unassigned.serialize,
        assignable: {
          id: @unassigned_team.id,
          mapping_id: @unassigned_team.enterprise_team_group_mappings.first&.external_group&.id,
          slug: @unassigned_team.slug,
          login: @unassigned_team.name,
          member_count: @unassigned_team.member_count,
          member_ids: @unassigned_team.member_user_ids
        }
      }],
    }
  end

  def payload
    Copilot::Payloads::Businesses::EnterpriseTeamSearch.new(
      business: @business,
      params: ActionController::Parameters.new({})
    ).call
  end

  context "#call" do
    test "returns the expected payload" do
      assert_equal payload, expected_payload
    end

    test "returns the expected payload when there is a search query" do
      payload = Copilot::Payloads::Businesses::EnterpriseTeamSearch.new(
        business: @business,
        params: ActionController::Parameters.new({ q: "awesome" })
      ).call

      assert_equal payload[:teams].size, 1
      assert_equal payload[:teams].first[:assignable][:login], "Awesome-Team"
    end

    test "returns the expected path when there is a sort query" do
      payload = Copilot::Payloads::Businesses::EnterpriseTeamSearch.new(
        business: @business,
        params: ActionController::Parameters.new({ sort: "name_desc" })
      ).call

      assert_equal payload[:teams].size, 2
      assert_equal payload[:teams].first[:assignable][:login], "Unassigned-Team"
    end

    test "returns the expected path when there is a page query" do
      Copilot::Payloads::Businesses::StandaloneBase.stub_const(:PER_PAGE, 1) do
        payload = Copilot::Payloads::Businesses::EnterpriseTeamSearch.new(
          business: @business,
          params: ActionController::Parameters.new({ page: 2 })
        ).call

        assert_equal payload[:teams].size, 1
        assert_equal payload[:total], 2
        assert_equal payload[:teams].first[:assignable][:login], "Unassigned-Team"
      end
    end

    test "returns correct payload when a seat assignment is pending cancellation" do
      @seat_assignment.update_columns(pending_cancellation_date: Date.today)
      @enterprise_team_assignment.destroy

      refute_nil @seat_assignment.pending_cancellation_date

      payload = Copilot::Payloads::Businesses::EnterpriseTeamSearch.new(
        business: @business,
        params: ActionController::Parameters.new({})
      ).call

      assert_equal payload[:teams].size, 2
      assert_equal payload[:total], 2
    end
  end
end unless GitHub.single_business_environment?
