# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class ReconcileMeteredGheLicensesWithBillingPlatform < Base
      class Customer < ApplicationRecord::Domain::Users
        self.table_name = :customers
      end

      iterate_over :database_table, params: {
        model_class: Customer,
        columns: %i[metered_plan],
        conditions: "metered_plan = 1",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |id|
          business = Business.find_by(customer_id: id)
          next unless business.present?
          next unless business.eligible_for_metered_licensing?

          log "#{dry_run? ? "Would be reconciling" : "Reconciling"} GHE licenses with Billing Platform for metered customer #{id}"

          unless dry_run?
            ::Licensing::ReconcileLicensesWithBillingPlatformJob.perform_later(business)
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

  GitHub::Transitions::ReconcileMeteredGheLicensesWithBillingPlatform.new(args).run
end
