# typed: true
# frozen_string_literal: true

module Workbench
  class DetermineBillableCustomers < ::CloudEnvironments::Command
    attr_accessor :user

    sig { params(user: ::User).void }
    def initialize(user)
      @user = user
    end

    sig { override.returns(T::Array[Customer]) }
    def perform
      copilot_user = Copilot::Public::User.new(user)

      # If the user's selected a billable customer then it's the one and only option.
      #
      # At the time of writing (2025-05-14) this functionality is feature flagged, so everything below this is about
      # providing reasonable defaults if the user hasn't selected a billable customer.
      if copilot_user.billable_customer_ids.size > 0
        return Customer.where(id: copilot_user.billable_customer_ids).to_a
      end

      # The plan of record for the immediate term:
      #  * For CB/CE users Sparks are always owned by org
      #  * For Copilot Free Sparks are always owned by individuals
      #  * Pro/Pro+ - I think default to individual ownership. If an org is paying for a Pro/Pro+ license and they don’t like the user having control then they should pay for CB/CE licenses

      seat_customers = copilot_user.copilot_seats.map do |seat|
        seat.seat_assignment.owner&.business&.customer || seat.seat_assignment.owner&.customer
      end.compact

      # For CfB and CfE they cannot be individually owned, they *must* be owned by the provider of the seat.
      if copilot_user.has_ce_access? || copilot_user.has_cb_access?
        return seat_customers
      end

      # Pro, Pro+, Max users can pick themselves or any of their seats.
      if copilot_user.has_pro_access? || copilot_user.has_pro_plus_access? || copilot_user.has_max_access?
        [user.customer, *seat_customers].compact
      else
        # Everyone else can only pick themselves.
        [user.customer].compact
      end
    end
  end
end
