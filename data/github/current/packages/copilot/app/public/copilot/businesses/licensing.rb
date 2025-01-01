# typed: strict
# frozen_string_literal: true

module Copilot
  module Businesses
    module Licensing
      extend T::Helpers

      include Copilot::Businesses::Signatures
      include GitHub::Memoizer

      abstract!

      # Generate an array of Copilot seats that represent the Copilot SKUs that the business is
      # responsible for emitting. The result includes:
      #   - One seat without an organization ID (if any exist) to represent a Copilot for Business SKU linked to:
      #     * a non-GHEC enterprise seat.
      #     * a directly assigned user seat for a GHEC enterprise.
      #     * an org seat that was revoked to the enterprise.
      #   - One representative seat per organization (deduplicated by organization_id)
      #
      # These seats are used to determine the correct SKU to bill for each organization
      # within the business, as different organizations can have different Copilot plans.
      #
      # [Array<Copilot::Seat>] Deduplicated array of seats representing billing needs
      sig { returns(T::Array[Copilot::Seat]) }
      memoize def first_enterprise_seats_by_org_id
        result = []
        seats_with_org_id, seats_without_org_id = enterprise_owned_seats.partition do |seat|
          if seat.seat_assignment&.owner_type == "Business" && seat.organization_id.nil?
            false
          else
            true
          end
        end

        # Add a single seat, without an org an id, to signal that we need to bill
        # at least one Copilot for Business SKU seat for this business.
        result << seats_without_org_id.first if seats_without_org_id.any?

        # Add any org seats, deduplicating by org id. Again, we need one seat for each
        # org so we can assign the correct sku to bill for for that seat.
        # Different orgs in the same enterprise can have different Copilot plans.
        result.concat(seats_with_org_id.uniq(&:organization_id))

        result
      end

      # Loads all of the enterprise seats for the given organization ids and sorts them by copilot_sku,
      # in the following order:
      #   Copilot Business trials > Copilot Enterprise trials > Copilot Enterprise > Copilot Business = Copilot Standalone
      sig { returns(T::Array[Copilot::Seat]) }
      memoize def seats_sorted_by_copilot_sku
        first_seat_ids_by_org = []
        # This is a list of seats ids that are owned by the enterprise. They may be shared with the
        # enterprise's organizations if org seat assignments have been revoked to the enterprise.
        enterprise_owned_seat_ids = first_enterprise_seats_by_org_id.map(&:id)

        # For each organization, find its first seat that isn't shared with the business, if one exists.
        seat_info_by_org_id.each do |_, seats_infos|
          next unless seats_infos.any?

          # Find the first seat for this org that isn't in enterprise_seat_ids
          non_shared_seat = seats_infos.find { |seat_info| !enterprise_owned_seat_ids.include?(seat_info[0]) }

          # Only add non-shared seats (no fallback)
          first_seat_ids_by_org << non_shared_seat[0] if non_shared_seat
        end

        # Add business seats to the list of org seats. Don't deduplicate these seats by org id, because we could
        # have revoked org seat assignments AND seat assignments that still belong to the org.
        # This is because the EnterpriseSeatEmissionJob is called for each seat, by org. Enterprise assignments
        # are grouped under an org id of 0, and we want to make sure we emit for those too.
        first_seat_ids_by_org += enterprise_owned_seat_ids

        # Get the actual Copilot::Seat records for the first seat of each org so we can find the copilot_sku
        first_seats_by_org = Copilot::Seat.where(id: first_seat_ids_by_org)

        GitHub::PrefillAssociations.prefill_batch_method(first_seats_by_org, :copilot_sku)

        first_seats_by_org.sort_by do |seat|
          Copilot::Seat.priority_for_copilot_sku(seat.copilot_sku)
        end
      end

      # Returns a hash mapping organization IDs to arrays of user IDs who have Copilot seats.
      # The hash is structured as follows:
      #   - Key 0: Contains all user IDs with seats owned directly by the business
      #   - Other keys: Organization IDs, each containing user IDs with seats in that organization
      #
      # This method ensures that:
      #   1. Business-owned seats are grouped under key 0
      #   2. Organization seats are grouped under their respective organization IDs
      #   3. Some seats may appear in multiple groups if they're shared between business and orgs
      #
      # The resulting hash is used for billing calculations to ensure users are only billed once,
      # even if they have seats in multiple organizations within the same enterprise.
      sig { returns(T::Hash[Integer, T::Array[Integer]]) }
      memoize def seats_sorted_by_copilot_sku_by_org_id
        sorted_seats = seats_sorted_by_copilot_sku

        # Here we need to regroup seats by organization_id, making sure that we include
        # seats that were revoked to the enterprise in both:
        #   * the enterprise's key (0)
        #   * the organization's key (the org's id).
        multi_grouped = Hash.new { |h, k| h[k] = [] }
        sorted_seats.each do |seat|
          # Add to business group if needed
          if seat.seat_assignment&.owner_type == "Business"
            multi_grouped[0] << seat
          end

          # Also add to org group if it has an org_id
          if seat.organization_id
            multi_grouped[seat.organization_id] << seat
          end
        end

        # Finally, we get ALL the seats for each entry in the multi_grouped hash
        # and store the assigned user ids by the org_ids in the hash.
        multi_grouped.inject({}) do |acc, (org_id, _)|
          # Use 0 as the key for direct assignment for business users to ensure we have an ID that is not nil and doesn't clash with any org IDs
          org_id = 0 if org_id.nil?
          acc[org_id] = if org_id.zero?
            enterprise_owned_seats.map(&:assigned_user_id).compact
          else
            seat_info_by_org_id[org_id]&.map { |seat_arr| seat_arr[2] } # we only care about the user ids
          end
          acc
        end
      end

      # Returns a hash with the organization id as the key and the value is an array
      # of Copilot::Seat info: [id, organization_id, assigned_user_id]
      # This was refactored to use pluck in order to reduce the memory usage of the query.
      sig { returns(T::Hash[T.nilable(Integer), T::Array[T::Array[Integer]]]) }
      memoize def seat_info_by_org_id
        Copilot::Seat
          .includes(:seat_assignment)
          .where(organization_id: business_object.organization_ids)
          .pluck(:id, :organization_id, :assigned_user_id)
          .group_by { |_id, organization_id, _assigned_user_id| organization_id }
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def enterprise_owned_seats
        Copilot::Seat.includes(:seat_assignment).for_owner(business_object)
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

            user_ids = if seat[:org_id]
              seat_info_by_org_id[seat[:org_id]]&.map { |seat_arr| seat_arr[2] }
            else
              Copilot::Seat.business_owned(business_object).map(&:assigned_user_id).compact
            end
            acc[license] = (acc.fetch(license, [])) + user_ids
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

        enterprise_trial_seats_staff = org_seats_by_license
          .fetch(:COPILOT_ENTERPRISE_TRIAL_SEAT_STAFF, [])
          .filter(&deduplicate_ids)

        # next get all unique seats that are not in a trial org
        enterprise_seats = org_seats_by_license
          .fetch(:COPILOT_ENTERPRISE_SEAT, [])
          .filter(&deduplicate_ids)

        # Business seats are billed at the business rate, and can't appear in either of the other two sets of seats
        business_seats = org_seats_by_license
          .fetch(:COPILOT_FOR_BUSINESS_SEAT, [])
          .filter(&deduplicate_ids)

        { enterprise: enterprise_seats.size, business: (business_seats + enterprise_trial_seats + enterprise_trial_seats_staff).size }
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
