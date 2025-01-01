# typed: strict
# frozen_string_literal: true

module Copilot
  module Metrics
    module Aggregators
      class UserOnboarding < Copilot::Metrics::Aggregators::Base
        sig { returns(Integer) }
        def total_seats
          seat_ids.size
        end

        sig { returns(Integer) }
        def active_seats
          seat_ids_with_activity.size
        end

        sig { returns(Integer) }
        def inactive_seats
          (seat_ids_with_authentication - seat_ids_with_activity).size
        end

        sig { returns(Integer) }
        def dormant_seats
          (seat_ids - seat_ids_with_authentication - seat_ids_with_activity).size
        end

        private

        sig { returns(Date) }
        memoize def lookback_date
          start_date - LOOKBACK_DAYS.days
        end

        sig { returns(T::Set[Integer]) }
        memoize def seat_ids
          Copilot::SeatHistory
            .where(organization_id: owner.id).where(seat_created_at: ..end_date)
            .where("seat_deleted_at IS NULL OR seat_deleted_at > ?", start_date)
            .pluck(:seat_id)
            .to_set
        end

        sig { returns(T::Set[Integer]) }
        memoize def seat_ids_with_authentication
          Copilot::AuthenticationHistory
            .where(copilot_seat_id: seat_ids, authentication_date: lookback_date..end_date)
            .pluck(:copilot_seat_id)
            .to_set
        end

        sig { returns(T::Set[Integer]) }
        memoize def seat_ids_with_activity
          Copilot::ActivityHistory
            .where(copilot_seat_id: seat_ids, activity_date: lookback_date..end_date)
            .pluck(:copilot_seat_id)
            .to_set
        end
      end
    end
  end
end
