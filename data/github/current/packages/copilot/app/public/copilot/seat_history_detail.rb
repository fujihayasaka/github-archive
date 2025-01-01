# typed: strict
# frozen_string_literal: true

# {
#   seats_billed_in_full: 18,
#   prorations: [
#     { days: 15, count: 2 },
#     { days: 10, count: 1 },
#     { days: 5, count: 3},
#   ]
# }
# seats_billed_in_full – Seat billed from beginning to end of the cycle. ie: seat carried over from previous cycle
# prorations – Proration of seats added during the cycle
# days – days till the end of the cycle. i.e: days the seat was billed in that cycle
# count – number of seats added this day. This is count of individual user seats. So, for team or organization assignment, this number will be all users in that team/org (that are eligible and didn't have seats already)

module Copilot
  class SeatHistoryDetail
    include GitHub::Memoizer

    sig { returns(::Billing::Types::Account) }
    attr_reader :billable_owner

    sig { returns(Date) }
    attr_reader :start_date

    sig { returns(Date) }
    attr_reader :end_date

    sig { params(billable_owner: ::Billing::Types::Account, start_date: Date, end_date: Date).void }
    def initialize(billable_owner:, start_date:, end_date:)
      @billable_owner = billable_owner
      @start_date     = start_date
      @end_date       = end_date
    end

    sig { returns(T::Hash[Symbol, T.any(Integer, T::Array[T::Hash[Symbol, Integer]])]) }
    memoize def to_h
      {
        seats_billed_in_full: billed_in_full_count,
        prorations: prorations,
      }
    end

    private

    sig { returns(::ActiveRecord::Relation) }
    memoize def seat_histories
      if billable_owner.business?
        Copilot::SeatHistory.where(business: @billable_owner)
      else
        Copilot::SeatHistory.where(organization: @billable_owner)
      end
    end

    sig { returns(Integer) }
    def billed_in_full_count
      seat_histories.where(
        "seat_created_at <= ? AND (seat_deleted_at IS NULL OR seat_deleted_at >= ?)",
        start_date,
        end_date).count
    end

    sig { returns(T::Array[T::Hash[Symbol, Integer]]) }
    def prorations
      prorated_seats = T.cast(seat_histories.where("seat_created_at > ? AND seat_created_at <= ?", start_date, end_date).to_a,
                              T::Array[Copilot::SeatHistory])

      prorated_seats.each_with_object(Hash.new(0)) do |seat_history, proration_memo|
        days = ((end_date.to_time - seat_history.seat_created_at.to_time) / 1.day).to_i + 1
        proration_memo[days] += 1
      end.map { |days, count| { days: days, count: count } }.sort_by { |proration| proration[:days] }.reverse
    end
  end
end
