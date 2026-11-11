# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills billable_customer_id for users who have a Copilot seat through
# either the microsoftcopilot org (Copilot::MICROSOFTCOPILOT_ORG_ID) or any
# org belonging to the Microsoft Open Source enterprise/business
# (Copilot::MICROSOFT_OPEN_SOURCE_ENT_ID), and also have seats from other
# enterprises, but have not yet selected a billable customer.
#
# When a user has a seat in both Microsoft customers, prefers the Microsoft
# Open Source customer (1392418) over the Microsoft Copilot customer
# (12404746).
#
# Skips users who also have a seat from the GitHub customer (5018891) - those
# are staff and are handled by the staff backfill transition.
#
# Iterates over copilot_seats scoped to the relevant organization_ids.
# copilot_seats.organization_id is indexed, so this avoids scanning the full table.
#
# Usage:
#   bin/transition run lib/github/transitions/20260513005120_backfill_ms_billable_customer_id.rb
module GitHub
  module Transitions
    class BackfillMsBillableCustomerId < Base
      MS_OPEN_SOURCE_CUSTOMER_ID = T.let(1392418, Integer)
      MS_COPILOT_CUSTOMER_ID = T.let(12404746, Integer)
      GITHUB_CUSTOMER_ID = T.let(5018891, Integer)

      sig { override.void }
      def after_initialize
        ms_business = Business.find_by(id: Copilot::MICROSOFT_OPEN_SOURCE_ENT_ID)
        unless ms_business
          raise "Microsoft Open Source business (#{Copilot::MICROSOFT_OPEN_SOURCE_ENT_ID}) not found"
        end

        org_ids = ms_business.organizations.pluck(:id)
        org_ids << Copilot::MICROSOFTCOPILOT_ORG_ID
        org_ids = org_ids.map(&:to_i).uniq

        if org_ids.empty?
          raise "No organizations found for Microsoft Open Source business"
        end

        # Build the iterator dynamically since the org_id list is computed at
        # runtime from the Microsoft Open Source business.
        iter = Iterators::DatabaseTable.new(
          model_class: Copilot::Seat,
          columns: %i[id assigned_user_id],
          conditions: "organization_id IN (#{org_ids.join(",")})",
        )
        iter.transition = self
        iter.arguments = arguments
        @iterator = iter
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        user_ids = items.values.map { |row| row[:assigned_user_id] }.uniq

        # Find users in this batch who have a copilot config with no billable_customer_id
        configs = Copilot::Configuration
          .where(configurable_type: "User", configurable_id: user_ids, billable_customer_id: nil)

        if configs.empty?
          log("No unset copilot configs for #{user_ids.size} users in this batch, skipping.")
          return
        end

        eligible_users = T.let([], T::Array[[User, Integer]])
        users_by_id = User.where(id: configs.map(&:configurable_id)).index_by(&:id)

        # Load all non-revoked seats for these users to compute customer IDs
        # without going through Copilot::Public::User.for (which triggers
        # the Copilot authorization flow and Vexi feature-flag checks that
        # fail in transition workers).
        all_seats = Copilot::Seat
          .joins(:seat_assignment)
          .where(assigned_user_id: configs.map(&:configurable_id))
          .where(copilot_seat_assignments: { access_revoked_at: nil })
          .includes(seat_assignment: { owner: :business })

        seats_by_user = all_seats.group_by(&:assigned_user_id)

        configs.each do |config|
          user = users_by_id[config.configurable_id]
          next unless user

          user_seats = seats_by_user[user.id] || []
          customer_ids = customer_ids_from_seats(user_seats)

          # Only target users with multiple enterprise seats
          next unless customer_ids.size > 1

          # Skip users who also have a GitHub seat (staff, handled elsewhere)
          if customer_ids.include?(GITHUB_CUSTOMER_ID)
            log("Skipping GitHub staff user: #{user.login} (id=#{user.id}, customer_ids=#{customer_ids})")
            next
          end

          # Prefer MS Open Source over MS Copilot when user has both
          target_customer_id =
            if customer_ids.include?(MS_OPEN_SOURCE_CUSTOMER_ID)
              MS_OPEN_SOURCE_CUSTOMER_ID
            elsif customer_ids.include?(MS_COPILOT_CUSTOMER_ID)
              MS_COPILOT_CUSTOMER_ID
            end

          next unless target_customer_id

          eligible_users << [user, target_customer_id]
          log("Eligible user: #{user.login} (id=#{user.id}, target=#{target_customer_id}, customer_ids=#{customer_ids})")
        end

        if eligible_users.empty?
          log("No eligible multi-seat users with target customer in batch of #{configs.size} configs.")
          return
        end

        if dry_run?
          log("Would update billable_customer_id for #{eligible_users.size} users")
        else
          log("Updating billable_customer_id for #{eligible_users.size} users")

          # Batch update configurations grouped by target_customer_id so we
          # issue one UPDATE per customer instead of one per user.
          eligible_users.group_by { |_user, customer_id| customer_id }.each do |target_customer_id, group|
            user_ids = group.map { |user, _| user.id }

            write_to(model_class: Copilot::Configuration) do
              Copilot::Configuration
                .where(configurable_type: "User", configurable_id: user_ids, billable_customer_id: nil)
                .update_all(billable_customer_id: target_customer_id)
            end
          end

          # Emit the license change events per user. We do this outside the
          # write_to block since instrumentation is not a DB write. We use
          # Copilot::Instrumenter directly rather than set_billable_customer_id!
          # which calls Public::User.for and triggers Vexi feature-flag checks
          # that fail in transition workers.
          eligible_users.each do |user, target_customer_id|
            Copilot::Instrumenter.instrument(
              Copilot::Events::COPILOT_LICENSE_OR_BILLABLE_CUSTOMER_CHANGE,
              {
                user_id: user.id,
                billable_customer_id: target_customer_id,
                copilot_tracking_id: user.analytics_tracking_id,
                reset_quota: false,
              },
            )

            log("Set billable_customer_id=#{target_customer_id} for #{user.login}")
          end
        end
      end

      private

      # Replicates Copilot::Public::User#customer_ids_from_seats without
      # going through the authorization/Vexi path.
      sig { params(seats: T::Array[Copilot::Seat]).returns(T::Array[Integer]) }
      def customer_ids_from_seats(seats)
        ids = seats.filter_map do |seat|
          assignment = seat.seat_assignment
          next unless assignment

          owner = assignment.owner

          if owner.is_a?(::Business)
            owner.customer&.id
          elsif owner.is_a?(::Organization)
            ob = owner.business
            if ob
              ob.customer&.id
            else
              owner.customer&.id
            end
          end
        end
        ids.uniq
      end
    end
  end
end

# Run as a single process if this script is run directly
if $0 == __FILE__
  # See the transition arguments class for information about standard
  # arguments and their default values. If you require additional arguments,
  # pass them via `additional_arguments: %w(foo)` to the `parse` method.
  args = GitHub::Transitions::Arguments.parse(ARGV)

  GitHub::Transitions::BackfillMsBillableCustomerId.new(args).run
end
