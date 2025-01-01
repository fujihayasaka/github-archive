# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillVssLicensesToLicensify < Base
      class BundledLicenseAssignment < ApplicationRecord::Domain::Billing
        self.table_name = :bundled_license_assignments
      end

      iterate_over :database_table, params: {
        model_class: BundledLicenseAssignment,
        columns: %i[id],
        conditions: "user_id IS NOT NULL AND business_id IS NOT NULL AND revoked = false"
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        batch_bla_ids = items.keys.uniq

        log "Backfilling VSS licenses from bundled license assignment IDs: #{batch_bla_ids.join(', ')}"

        backfill_blas = BundledLicenseAssignment.where(id: batch_bla_ids)

        business_ids = backfill_blas.pluck(:business_id).compact.uniq
        businesses = Business.where(id: business_ids).index_by(&:id)

        backfill_blas.each do |bla|
          log "#{dry_run? ? "Would be backfilling" : "Backfilling"} VSS license from bundled license assignment ID #{bla.id}"
          next if dry_run?

          business = businesses[bla.business_id]

          GlobalInstrumenter.instrument("licensing.bundled_license_assignment_association_changed", {
            change_type: :USER_ASSIGNED,
            subscription_id: bla.subscription_id,
            business: business,
            user_id: bla.user_id,
            previous_user_id: nil
          })
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

  GitHub::Transitions::BackfillVssLicensesToLicensify.new(args).run
end
