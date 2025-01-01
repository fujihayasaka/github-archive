# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class SyncCustomersMeteredViaAzure < Base
      class Customer < ApplicationRecord::Domain::Users
        self.table_name = :customers
      end

      iterate_over :database_table, params: {
        model_class: Customer,
        columns: %i[azure_subscription_id metered_via_azure],
        conditions: "azure_subscription_id IS NOT NULL AND metered_via_azure = false",
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        items.keys.each do |id|
          customer = ::Customer.find(id)
          next unless customer.business&.enterprise_agreements&.active&.any?

          log "#{dry_run? ? "Would be updating" : "Updating"} `metered_via_azure` flag for customer #{id}"

          unless dry_run?
            write_to(model_class: Customer) { customer.update!(metered_via_azure: true) }
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

  GitHub::Transitions::SyncCustomersMeteredViaAzure.new(args).run
end
