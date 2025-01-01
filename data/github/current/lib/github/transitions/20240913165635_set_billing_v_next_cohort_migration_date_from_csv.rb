# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SetBillingVNextCohortMigrationDateFromCsv < Base
      class BillingPlatformEnabledProduct < ApplicationRecord::Domain::Users
        self.table_name = :billing_platform_enabled_products
      end

      iterate_over :csv, params: {
        csv_file: "lib/github/transitions/20240913165635_set_billing_v_next_cohort_migration_date_from_csv.csv",
        csv_read_opts: { headers: true },
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log("Processing batch of #{items.size} items starting with row #{items.keys.first}")

        items.each do |(_, row)|
          customer_id = row[:customerID]
          cohort_name = row[:cohort_name]
          planned_migration_date = DateTime.strptime(row[:planned_migration_date], "%m/%d/%Y")

          customer = Customer.find_by(id: customer_id)
          next log("Skipping customer #{customer_id} because Customer record does not exist") if customer.nil?
          next log("Skipping customer #{customer.name} because they're is already onboarded to vNext") if customer.billed_via_billing_platform?

          config = BillingPlatformEnabledProduct.find_or_initialize_by(customer_id: customer_id)
          if config.planned_migration_date.nil? || arguments[:force]
            if dry_run?
              log("Would have set planned migration date to #{planned_migration_date} for customer #{customer.name}")
            else
              config.planned_migration_date = planned_migration_date
              config.cohort_name = cohort_name
              write_to(model_class: BillingPlatformEnabledProduct) do
                config.save!
              end
              log("Set planned migration date to #{planned_migration_date} for customer #{customer.name}")
            end
          else
            log("Skipping customer #{customer.name} because it already has a planned migration date and 'force' flag is not set")
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
  args = GitHub::Transitions::Arguments.parse(ARGV, additional_arguments: %w(force))

  GitHub::Transitions::SetBillingVNextCohortMigrationDateFromCsv.new(args).run
end
