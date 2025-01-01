# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class PreviouslyBilledOrgSeatsFinder
      # This class is used to find the user ids of seats that have been revoked to the enterprise, but
      # have already been billed for at the organization level in the current billing cycle.
      # This is used to prevent double billing of seats that have been revoked from the org to the enterprise.
      sig { params(copilot_business: Copilot::Business, seat_user_ids: T::Array[Integer]).returns(T::Array[Integer]) }
      def self.find_already_billed_user_ids(copilot_business, seat_user_ids)
        new(copilot_business, seat_user_ids).find_already_billed_user_ids
      end

      sig { params(copilot_business: Copilot::Business, seat_user_ids: T::Array[Integer]).void }
      def initialize(copilot_business, seat_user_ids)
        @copilot_business = copilot_business
        @seat_user_ids = seat_user_ids
      end

      sig { returns(T::Array[Integer]) }
      def find_already_billed_user_ids
        enterprise_owned_seats = @copilot_business.enterprise_owned_seats.to_a
        # List of all seats owned by the enterprise that are assigned to the user ids we are considering.
        seats_to_check = enterprise_owned_seats.filter do |seat|
          @seat_user_ids.include?(seat.assigned_user_id)
        end

        # Lookup table of the seats by their organization id.
        seats_by_org = seats_to_check.group_by(&:organization_id)

        # Handles case where the org emitted earlier in the day, and then a seat was revoked from the org.
        # Map of org id to its emission for today, if it exists.
        orgs_emitted_today = Copilot::SeatEmission
          .where(owner_id: seats_to_check.pluck(:organization_id).uniq, owner_type: "Organization")
          .where("quantity > 0")
          .emitted_today
          .distinct
          .pluck(:owner_id, :emission)
          .to_h

        # Return the user ids of the seats that have been emitted today.
        orgs_emitted_today.inject([]) do |memo, (org_id, emission)|
          next memo unless emission

          # Get user IDs for this organization's seats
          org_seats = seats_by_org[org_id] || []
          org_seat_user_ids = org_seats.map(&:assigned_user_id)

          payload = emission.fetch("billing_platform_payload", nil)

          if payload.present? && payload["actor_ids"].present?
            memo + org_seat_user_ids.intersection(payload["actor_ids"])
          else
            # For orgs using meuse assume all seats for that org have been billed
            memo.concat(org_seat_user_ids)
          end
        end
      end
    end
  end
end
