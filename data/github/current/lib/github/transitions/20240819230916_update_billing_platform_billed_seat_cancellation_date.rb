# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class UpdateBillingPlatformBilledSeatCancellationDate < Base

      ## This was a one-off transition for correcting copilot seat cancellation dates during September 2024. If we want to
      ## reuse this in the future, make sure to update the two dates in the conditions block to the correct updated dates
      ## as this transition runs for the seats in the CURRENT month.
      iterate_over :database_table, params: {
        model_class: Copilot::SeatAssignment,
        conditions: "pending_cancellation_date IS NOT NULL AND pending_cancellation_date BETWEEN '2024-9-02' AND '2024-09-30'",
        columns: [:id, :organization_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log "Starting transition #{self.class.to_s.underscore}"
        if dry_run?
          log "Would have updated #{items.count} seat assignments"
        else
          log "Updating #{items.count} seat assignments"
          items.each do |item|
            org_id = item[1][:organization_id]
            org = Organization.find_by(id: org_id)
            customer = org&.business&.customer
            if T.must(customer).billed_via_billing_platform?
              seat_assignment = Copilot::SeatAssignment.find_by(id: item[0])
              if seat_assignment.nil?
                log "No seat assignments found for seat assignment with id #{item[0]}"
                next
              end
              write_to(model_class: Copilot::SeatAssignment) do
                seat_assignment.update(pending_cancellation_date: (Time.now.utc.beginning_of_month.in_time_zone + 1.month).in_time_zone)
              end
            end
          end
        end
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

  GitHub::Transitions::UpdateBillingPlatformBilledSeatCancellationDate.new(args).run
end
