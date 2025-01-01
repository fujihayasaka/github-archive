# typed: strict
# frozen_string_literal: true

require "test_helper"

class Copilot::ActivityHistoryTest < GitHub::TestCase
  include CopilotTestHelper # automatically disables Copilot feature flags

  test "factory works" do
    activity = create(:copilot_activity_history)
    assert activity.persisted?
  end

  test "organization lookup" do
    seats = []
    seat = create(:copilot_seat)
    create(:copilot_activity_history, seat: seat)
    org = seat.organization

    seats << seat
    5.times do
      seater = create(:copilot_seat, organization: seat.organization)
      seats << seater
      create(:copilot_activity_history, seat: seater)
    end
    assert_equal 6, seats.count
    assert_equal 6, Copilot::ActivityHistory.for_organization(org).count
  end

  test "business lookup" do
    seat_assignment = create(:copilot_seat_assignment, :enterprise_team)
    enterprise_team = seat_assignment.assignable
    business = enterprise_team.business
    first_member = User.find_by(id: enterprise_team.member_user_ids.first)
    last_member = User.find_by(id: enterprise_team.member_user_ids.last)

    first_seat = create(:copilot_seat, :enterprise_team_member, assigned_user: first_member, seat_assignment: seat_assignment)
    create(:copilot_activity_history, seat: first_seat)
    last_seat = create(:copilot_seat, :enterprise_team_member, assigned_user: last_member, seat_assignment: seat_assignment)
    create(:copilot_activity_history, seat: last_seat)

    assert_equal 2, Copilot::ActivityHistory.for_business(business).count
  end
end if GitHub.copilot_enabled?
