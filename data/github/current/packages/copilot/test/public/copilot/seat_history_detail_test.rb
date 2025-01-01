# typed: true
# frozen_string_literal: true

require "test_helper"

class Copilot::SeatHistoryDetailTest < GitHub::TestCase
  fixtures do
    @organization = create(:copilot_for_business_enabled_organization)
    @business = @organization.business
  end

  def create_history(date, delete_at_date: nil)
    travel_to(date) do
      user = create(:user)
      @organization.add_member(user)
      seat = create(:copilot_seat, organization: @organization, assigned_user: user, created_at: date)
      seat.reload
      history = seat.seat_history
      history.update!(seat_deleted_at: delete_at_date) if delete_at_date

      assert_equal seat.created_at.to_date, history.seat_created_at
      assert_equal @organization.current_metered_billing_cycle_starts_at.to_date, history.billing_cycle_start_date
      assert_equal @organization.next_metered_billing_cycle_starts_at.to_date - 1.day, history.billing_cycle_end_date
    end
  end

  test "creates seat history" do
    date = Date.new(2020, 1, 1)

    travel_to(date) do
      seat = create(:copilot_seat)
      seat.reload
      history = seat.seat_history

      assert_equal seat.assigned_user_id, history.assigned_user_id
      assert_equal seat.organization.current_metered_billing_cycle_starts_at.to_date, history.billing_cycle_start_date
      assert_equal seat.organization.next_metered_billing_cycle_starts_at.to_date, history.billing_cycle_end_date
      assert_equal seat.created_at.to_date, history.seat_created_at

      seat.destroy!
      history.reload
      assert_equal date, history.seat_deleted_at
    end
  end

  test "creates seat history upon deletion one didn't exist" do
    date = Date.new(2020, 1, 1)

    travel_to(date) do
      seat = create(:copilot_seat)
      seat_id = seat.id
      seat.reload
      seat.seat_history.destroy!

      seat.reload
      seat.destroy!

      history = Copilot::SeatHistory.find_by(seat_id: seat_id)

      assert_equal date, T.must(history).seat_deleted_at
    end
  end
end if GitHub.copilot_enabled?
