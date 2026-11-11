# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# Backfills billable_customer_id for users who have a Copilot seat through
# the GitHub org (Copilot::GITHUB_ORG_ID) and also have seats from other
# enterprises, but have not yet selected a billable customer. Sets
# billable_customer_id to the customer belonging to the GitHub org's business.
#
# Iterates over copilot_seats scoped to Copilot::GITHUB_ORG_ID.
# copilot_seats.organization_id is indexed, so this avoids scanning the full table.
#
# Usage:
#   bin/transition run lib/github/transitions/20260422191945_backfill_staff_billable_customer_id.rb
module GitHub
  module Transitions
    class BackfillStaffBillableCustomerId < Base
      iterate_over :database_table, params: {
        model_class: Copilot::Seat,
        columns: %i[id assigned_user_id],
        conditions: "organization_id = #{Copilot::GITHUB_ORG_ID}",
      }

      # Microsoft customer IDs to skip (EMU, Open Source, Copilot)
      MICROSOFT_CUSTOMER_IDS = T.let([5328689, 1392418, 12404746].freeze, T::Array[Integer])

      sig { override.void }
      def after_initialize
        github_org = Organization.find_by(id: Copilot::GITHUB_ORG_ID)
        unless github_org&.business
          raise "GitHub org (#{Copilot::GITHUB_ORG_ID}) has no business"
        end

        target = github_org.business&.customer&.id
        unless target
          raise "GitHub org's business has no customer"
        end

        @target_customer_id = T.let(target, T.nilable(Integer))
      end

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        target_customer_id = T.must(@target_customer_id)
        user_ids = items.values.map { |row| row[:assigned_user_id] }.uniq

        # Find users in this batch who have a copilot config with no billable_customer_id
        configs = Copilot::Configuration
          .where(configurable_type: "User", configurable_id: user_ids, billable_customer_id: nil)

        if configs.empty?
          log("No unset copilot configs for #{user_ids.size} users in this batch, skipping.")
          return
        end

        eligible_users = T.let([], T::Array[User])
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

          # Only set if the target customer is among the user's seats
          next unless customer_ids.include?(target_customer_id)

          # Skip users who also have seats from Microsoft enterprises
          if (customer_ids & MICROSOFT_CUSTOMER_IDS).any?
            log("Skipping Microsoft user: #{user.login} (id=#{user.id}, customer_ids=#{customer_ids})")
            next
          end

          eligible_users << user
          log("Eligible user: #{user.login} (id=#{user.id}, customer_ids=#{customer_ids})")
        end

        if eligible_users.empty?
          log("No eligible multi-seat users with target customer in batch of #{configs.size} configs.")
          return
        end

        if dry_run?
          log("Would update billable_customer_id for #{eligible_users.size} users to #{target_customer_id}")
        else
          log("Updating billable_customer_id for #{eligible_users.size} users to #{target_customer_id}")
          eligible_users.each do |user|
            config = Copilot::Configuration.find_by(configurable: user)
            next unless config

            write_to(model_class: Copilot::Configuration) do
              config.update!(billable_customer_id: target_customer_id)
            end

            # Emit the license change event via Copilot::Instrumenter directly
            # rather than set_billable_customer_id! which calls Public::User.for
            # and triggers Vexi feature-flag checks that fail in transition workers.
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

  GitHub::Transitions::BackfillStaffBillableCustomerId.new(args).run
end
