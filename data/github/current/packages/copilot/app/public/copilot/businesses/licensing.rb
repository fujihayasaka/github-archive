# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Licensing
      extend T::Helpers
      extend T::Sig

      include Copilot::Businesses::Signatures
      include GitHub::Memoizer

      abstract!

      # Loads all of the enterprise seats for the given organization ids and sorts them by copilot_sku,
      # in the following order:
      #   Copilot Business trials > Copilot Enterprise trials > Copilot Enterprise > Copilot Business = Copilot Standalone
      sig { returns(T::Array[Copilot::Seat]) }
      memoize def seats_sorted_by_copilot_sku
        # Optimize this further by only passing the first seat per org to get the copilot_sku for each org
        first_seats_by_org = seats_by_org_id.values.map(&:first).compact
        GitHub::PrefillAssociations.prefill_batch_method(first_seats_by_org, :copilot_sku)

        first_seats_by_org.sort_by do |seat|
          Copilot::Seat.priority_for_copilot_sku(seat.copilot_sku)
        end
      end

      sig { returns(T::Hash[Integer, T::Array[Integer]]) }
      memoize def seats_sorted_by_copilot_sku_by_org_id
        sorted_seats = seats_sorted_by_copilot_sku

        sorted_seats.group_by { |seat| seat.organization_id }.inject({}) do |acc, (org_id, _)|
          acc[org_id] = seats_by_org_id[org_id]&.map(&:assigned_user_id) # we only care about the user ids
          acc
        end
      end

      sig { returns(T::Hash[T.nilable(Integer), T::Array[Copilot::Seat]]) }
      memoize def seats_by_org_id
        Copilot::Seat.where(organization_id: business_object.organization_ids)
                     .group_by(&:organization_id)
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
            acc[license] = (acc.fetch(license, [])) + seats_by_org_id[seat[:org_id]]&.map(&:assigned_user_id)
            acc
          end

        # These are free, we won't bill for them at all.
        business_trial_seats = org_seats_by_license.fetch(:COPILOT_FOR_BUSINESS_TRIAL_SEAT, []).uniq

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

      sig { abstract.returns(::Business) }
      def business_object; end
    end
  end
end
