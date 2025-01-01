# typed: strict
# frozen_string_literal: true

module Copilot
  module Billing
    class CancellationTelemetry
      include GitHub::Memoizer
      include Copilot::Helpers

      SeatCancellationPayload = T.type_alias do
        {
          payment_submission_target: String,
          num_pending_cancelled_seats: Integer,
          num_new_pending_cancelled_seats: Integer,
          num_immediately_cancelled_seats: Integer,
        }
      end

      SeatCancellationData = Struct.new(
        :num_pending_cancelled_seats,
        :num_new_pending_cancelled_seats,
        :num_immediately_cancelled_seats
      )

      EnterpriseSeatDetail = T.type_alias do
        {
          assigned_user_id: Integer,
          pending_cancellation_date: T.nilable(Date),
          updated_at: Date
        }
      end

      sig { returns(T.any(::Business, ::Organization)) }
      attr_reader :owner

      # This value is used to further filter the set of seats pending cancellation.
      # It is only used when finding seats for an organization that belongs to a parent business.
      sig { returns(T::Set[Integer]) }
      attr_reader :ids_with_active_seat

      sig { params(owner: T.any(::Business, ::Organization), ids_with_active_seat: T::Set[Integer]).void }
      def initialize(owner, ids_with_active_seat = Set.new)
        @owner = owner
        @ids_with_active_seat = ids_with_active_seat
      end

      # extra_emission_data provides additional information about seats that is required by our data team.
      # It is not directly needed by the billing system, and so is kept separate from the emission payload properties.
      sig { returns(SeatCancellationPayload) }
      memoize def seat_cancellation_data
        with_read do
          {
            payment_submission_target: payment_submission_target,
            num_pending_cancelled_seats: num_pending_cancelled_seats,
            num_new_pending_cancelled_seats: num_new_pending_cancelled_seats,
            num_immediately_cancelled_seats: num_immediately_cancelled_seats,
          }
        end
      end

      # payment_submission_target indicates how owner manages their payments to GitHub.
      # Broadly speaking, this can be one of:
      #   * azure
      #   * zuora
      #   * unknown — this should not happen, but we need a fallback value.
      sig { returns(String) }
      def payment_submission_target
        # The owner of the emittable is the entity that owns the seat assignments and seats.
        # This is not necessarily the entity that is billed for the seats.
        # So, we explicitly get the billable owner to determine the payment submission target.
        billable = owner.billable_owner

        return "zuora" if billable.zuora_account?
        return "azure" if billable.metered_via_azure?

        # We should rarely land here, but we need a fallback value.
        # Log it so we can be aware of when it happens.
        # Currently there are ~300 known businesses that should be configured with a zuora account,
        # but are not. Product + billing are working to correct this.
        GitHub.logger.info("Unable to determine payment_submission_target for billable owner",
          "gh.code.namespace" => self.class.name,
          "gh.copilot.owner.id" => billable.id,
          "gh.copilot.owner.type" => billable.class.name,
        )
        "unknown"
      end

      sig { returns(Integer) }
      memoize def num_pending_cancelled_seats
        if is_standalone_business?
          return all_standalone_enterprise_seats.inject(0) do |sum, (_, assignments)|
            next sum if assignments.any? { |a| a["pending_cancellation_date"].nil? }

            if assignments.any? { |a| a["pending_cancellation_date"].between?(billing_cycle_dates.begin, billing_cycle_dates.end) }
              sum += 1
            end
            sum
          end
        end

        all_pending_cancellation_org_seats.count
      end

      sig { returns(Integer) }
      memoize def num_new_pending_cancelled_seats
        if is_standalone_business?
          # Get all seats along with details about the seat assignments. We need all of them becuase we need to know
          # if a user has more than one seat, and we'd have to do perform multiple queries otherwise.
          # Opting to do this as a raw sql query, returning hashes, to avoid the overhead of instantiating ActiveRecord objects
          # for a potentially large number of seats.
          return all_standalone_enterprise_seats.inject(0) do |sum, (_, assignments)|
            next sum if assignments.any? { |a| a["pending_cancellation_date"].nil? }

            if assignments.any? do |a|
              a["updated_at"].between?(occurred_today.begin, occurred_today.end) &&
              a["pending_cancellation_date"].between?(billing_cycle_dates.begin, billing_cycle_dates.end)
            end
              sum += 1
            end

            sum
          end
        end

        # At this point, organization_seats will contain a filtered set of seats for the organization.
        # If applicable, it exlcudes any users who have at least one active seat, not pending cancelltion,
        # in another org, under the same parent enterprise.
        # Now, we can count up the seats that are pending cancellation, but were not pending cancellation yesterday.
        all_pending_cancellation_org_seats
          .where(seat_assignment: { updated_at: occurred_today })
          .count
      end

      # Get all the seats cancelled today.
      # We expect this number to be highest on the first day of the billing cycle,
      # as any seat assignments pending cancellation will have ben canceled on that day.
      sig { returns(Integer) }
      memoize def num_immediately_cancelled_seats
        return 0 unless GitHub.flipper[:copilot_immediate_cancellation_telemetry].enabled?

        base_query = Copilot::SeatHistory.where(owner_id: owner.id, owner_type: owner.class.name, seat_deleted_at: occurred_today)

        if is_standalone_business?
          cancelled_seats = base_query.to_a

          # First check raw total of how many seats were cancelled today.
          estimated_deleted_count = cancelled_seats.size

          # Next, using the ids of the users who had a seat cancelled today, check how many of them
          # have at least one active seat. This seat can still be pending cancellation, it just can't
          # have been cancelled today.
          assigned_user_ids = cancelled_seats.map(&:assigned_user_id)
          user_with_seats_count = enterprise_seats
            .where(assigned_user_id: assigned_user_ids)
            .where("copilot_seat_assignments.assignable_id IN (
              SELECT sa1.assignable_id
              FROM copilot_seat_assignments sa1
              INNER JOIN copilot_seat_assignments sa2 ON sa1.assignable_id = sa2.assignable_id
              WHERE sa1.pending_cancellation_date BETWEEN ? AND ?
              OR sa2.pending_cancellation_date IS NULL
            )", billing_cycle_dates.begin, billing_cycle_dates.end)
            .group(:assigned_user_id)
            .count
            .count

          return [estimated_deleted_count - user_with_seats_count, 0].max
        end

        if has_parent_business?
          # If a seat was cancelled today, but the user has at least one active seat in another org,
          # the cancellation does not materially impact ARR. Don't count it.
          base_query = base_query.where.not(assigned_user_id: ids_with_active_seat)
        end

        base_query.count
      end

      private

      sig { returns(T.any(Copilot::Business, Copilot::Organization)) }
      memoize def copilot_owner
        if owner.is_a?(::Business)
          Copilot::Business.new(T.cast(owner, ::Business))
        else
          Copilot::Organization.new(T.cast(owner, ::Organization))
        end
      end

      # Returns all ACTIVE organization seats for the microsoft Copilot org.
      # Otherwise, returns all seats for the organization, according to rules explained in the comments in the method.
      sig { returns(ActiveRecord::Relation) }
      memoize def organization_seats
        return active_msft_copilot_seats if owner.id == Copilot::MS_COPILOT_ORG_ID

        base_query = Copilot::Seat.for_organization(owner)

        if has_parent_business?
          # Here, we omit any users that have at least one active seat this billing period.
          # This can even include a seat that is already pending cancellation.
          # We do this because if they do have other active seats, additional pending cancellations don't impact ARR.
          return base_query.where.not(assigned_user_id: ids_with_active_seat)
        end

        # If we have a standalone organization, we know that any seats tied to seat assignments
        # that are pending cancellation should be counted.
        #
        # We can say this because the user is guaranteed to have only one seat within the organization.
        #
        # If the user has a seat in another standalone organization, or an organization belonging
        # to a parent business, they will have separate seat assignments, and will be billed for those
        # accordingly.
        #
        base_query
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def enterprise_seats
        Copilot::Seat.for_standalone_business(owner)
      end

      # Return all active seats for the microsoft Copilot org.
      sig { returns(ActiveRecord::Relation) }
      memoize def active_msft_copilot_seats
        Copilot::Seat
          .joins("INNER JOIN copilot_aggregate_usage_details on copilot_aggregate_usage_details.user_id = copilot_seats.assigned_user_id")
          .for_organization(owner)
          .where("copilot_aggregate_usage_details.updated_at > ?", 24.hours.ago)
      end

      sig { returns(T::Boolean) }
      memoize def is_standalone_business?
        copilot_owner.copilot_standalone?
      end

      sig { returns(T::Boolean) }
      memoize def has_parent_business?
        owner.is_a?(::Organization) && T.cast(owner, ::Organization).business.present?
      end

      sig { returns(T::Range[Date]) }
      memoize def occurred_today
        Date.today.midnight..Date.tomorrow.midnight
      end

      sig { returns(T::Range[Date]) }
      memoize def billing_cycle_dates
        owner.current_metered_billing_cycle_starts_at..owner.next_metered_billing_cycle_starts_at
      end

      sig { returns(T::Hash[Integer, T::Array[EnterpriseSeatDetail]]) }
      memoize def all_standalone_enterprise_seats
        Copilot::Seat
          .find_by_sql("
            SELECT copilot_seats.assigned_user_id, copilot_seat_assignments.pending_cancellation_date, copilot_seat_assignments.updated_at
            FROM copilot_seats
            INNER JOIN copilot_seat_assignments ON copilot_seats.copilot_seat_assignment_id = copilot_seat_assignments.id
            WHERE copilot_seat_assignments.owner_id=#{owner.id.to_i}
            AND copilot_seat_assignments.owner_type = \"Business\"
            AND copilot_seat_assignments.assignable_type = \"EnterpriseTeam\"
          ")
          .group_by { |row| row["assigned_user_id"] }
      end

      sig { returns(ActiveRecord::Relation) }
      memoize def all_pending_cancellation_org_seats
        organization_seats
          .joins(:seat_assignment)
          .where(seat_assignment: { pending_cancellation_date: billing_cycle_dates })
      end
    end
  end
end
