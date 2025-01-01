# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Licensing
      extend T::Helpers

      include Copilot::Businesses::Signatures
      include GitHub::Memoizer

      abstract!

      # Loads all of the enterprise seats for the given organization ids and sorts them by copilot_sku,
      # in the following order:
      #   Copilot Business trials > Copilot Enterprise trials > Copilot Enterprise > Copilot Business = Copilot Standalone
      sig { returns(T::Array[Copilot::Seat]) }
      memoize def seats_sorted_by_copilot_sku
        first_seat_ids_by_org = seat_info_by_org_id.values.map(&:first).map { |seat_info| seat_info[0] if seat_info }.compact
        # Get the actual Copilot::Seat records for the first seat of each org so we can find the copilot_sku
        first_seats_by_org = Copilot::Seat.where(id: first_seat_ids_by_org)
        GitHub::PrefillAssociations.prefill_batch_method(first_seats_by_org, :copilot_sku)

        first_seats_by_org.sort_by do |seat|
          Copilot::Seat.priority_for_copilot_sku(seat.copilot_sku)
        end
      end

      sig { returns(T::Hash[Integer, T::Array[Integer]]) }
      memoize def seats_sorted_by_copilot_sku_by_org_id
        sorted_seats = seats_sorted_by_copilot_sku

        sorted_seats.group_by { |seat| seat.organization_id }.inject({}) do |acc, (org_id, _)|
          acc[org_id] = seat_info_by_org_id[org_id]&.map { |seat_arr| seat_arr[2] } # we only care about the user ids
          acc
        end
      end

      sig { returns(T::Hash[T.nilable(Integer), T::Array[Copilot::Seat]]) }
      memoize def seats_by_org_id
        Copilot::Seat.where(organization_id: business_object.organization_ids)
                     .group_by(&:organization_id)
      end

      # Returns a hash with the organization id as the key and the value is an array
      #   of Copilot::Seat info: [id, organization_id, assigned_user_id]
      # This was refactored to use pluck in order to reduce the memory usage of the query.
      sig { returns(T::Hash[T.nilable(Integer), T::Array[T::Array[Integer]]]) }
      memoize def seat_info_by_org_id
        Copilot::Seat.where(organization_id: business_object.organization_ids)
                     .pluck(:id, :organization_id, :assigned_user_id)
                     .group_by { |_id, organization_id, _assigned_user_id| organization_id }
      end

      # With mixed licensing, we need to know which license users are granted Copilot through, for billing purposes.
      # So, we can't simply get all distinct users among orgs, we have to prioritize the license they are granted.
      # We always bill at the highest level, so enterprise licenses win when partitioning users.
      sig { returns(T::Hash[Symbol, Integer]) }
      def copilot_enabled_members_count_by_license
        sorted_enterprise_seats = seats_sorted_by_copilot_sku

        # Collect all org ids associated with each sku type
        org_seats_by_license = sorted_enterprise_seats
          .map { |seat| { org_id: seat.organization_id, license: seat.copilot_sku } }
          .inject({}) do |acc, seat|
            license = seat[:license]

            acc[license] = (acc.fetch(license, [])) + seat_info_by_org_id[seat[:org_id]]&.map { |seat_arr| seat_arr[2] }
            acc
          end

        # These are free, we won't bill for them at all.
        business_trial_seats = org_seats_by_license.fetch(:COPILOT_FOR_BUSINESS_TRIAL_SEAT, []).uniq
        # Inform the customers trying Digital Front Door on their enterprise account how many free seats they're using
        return { enterprise: 0, business: (business_trial_seats).size } if business_object.digital_front_door?

        duped_ids = business_trial_seats.each_with_object({}) { |id, acc| acc[id] = true }
        deduplicate_ids = ->(id) { next false if duped_ids[id]; duped_ids[id] = true }

        # enterprise trial users need to be considered first, if a user has a seat in an enterprise trial org AND
        # an organization with an enterprise license, they should be billed at the business price.
        # Users with a business seat are similarly also billed at that rate.
        enterprise_trial_seats = org_seats_by_license
          .fetch(:COPILOT_ENTERPRISE_TRIAL_SEAT, [])
          .filter(&deduplicate_ids)

        # next get all unique seats that are not in a trial org
        enterprise_seats = org_seats_by_license
          .fetch(:COPILOT_ENTERPRISE_SEAT, [])
          .filter(&deduplicate_ids)

        # Business seats are billed at the business rate, and can't appear in either of the other two sets of seats
        business_seats = org_seats_by_license
          .fetch(:COPILOT_FOR_BUSINESS_SEAT, [])
          .filter(&deduplicate_ids)

        { enterprise: enterprise_seats.size, business: (business_seats + enterprise_trial_seats).size }
      end

      sig { returns(Integer) }
      def total_cost
        members_count_by_license = copilot_enabled_members_count_by_license

        members_count_by_license[:business].to_i * Copilot::COPILOT_BUSINESS_MONTHLY_BASE_PRICE +
        members_count_by_license[:enterprise].to_i * Copilot::COPILOT_ENTERPRISE_MONTHLY_BASE_PRICE
      end

      sig { returns(T::Boolean) }
      memoize def has_unconfigured_organizations?
        return false if copilot_standalone?
        return false if unconfigured_organizations.empty?

        unconfigured_organizations.size > 0
      end

      sig { returns(T::Array[Copilot::Organization]) }
      memoize def unconfigured_organizations
        copilot_organizations.inject([]) do |memo, copilot_org|
          memo << copilot_org if copilot_org.copilot_enabled? && copilot_org.copilot_plan_unconfigured? && !copilot_org.has_trial?
          memo
        end
      end

      sig { abstract.returns(::Business) }
      def business_object; end
    end
  end
end
