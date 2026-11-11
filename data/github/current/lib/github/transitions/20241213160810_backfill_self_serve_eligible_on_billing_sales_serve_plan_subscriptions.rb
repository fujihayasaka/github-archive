# typed: strict
# frozen_string_literal: true

require "#{Rails.root}/config/environment"

# To learn more about transitions, checkout the documentation on The Hub:
# https://thehub.github.com/epd/engineering/products-and-services/dotcom/transitions/
module GitHub
  module Transitions
    class BackfillSelfServeEligibleOnBillingSalesServePlanSubscriptions < Base
      include T::Sig

      class SalesServePlanSubscription < ApplicationRecord::Domain::Billing
        self.table_name = :billing_sales_serve_plan_subscriptions
      end

      iterate_over :database_table, params: {
        model_class: SalesServePlanSubscription,
        conditions: "self_serve_eligible IS NULL",
        columns: %i[zuora_subscription_id],
      }

      sig { override.params(items: Iterators::Items).void }
      def process_batch(items)
        log("batch start item_count = #{items.count}")

        items.each do |id, values|
          log("start billing_sales_serve_plan_subscriptions.id = #{id}")

          if dry_run?
            log("skip (dryrun) billing_sales_serve_plan_subscriptions.id = #{id}")
            next
          end

          zuora_subscription_id = T.let(values[:zuora_subscription_id], String)
          zuora_subscription = ::Billing::Zuora::SalesManagedSubscription.fetch_by_subscription_id(zuora_subscription_id)

          if zuora_subscription.nil?
            log("skip (zuora subscription not found) billing_sales_serve_plan_subscriptions.id = #{id}")
            next
          end

          write_to(model_class: ::Billing::SalesServePlanSubscription) do
            ::Billing::Zuora::SalesManagedEnterpriseSubscriptionSynchronizer.new(zuora_subscription).sync_sales_serve_plan_subscription
          end

          log("complete billing_sales_serve_plan_subscriptions.id = #{id}")
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

  GitHub::Transitions::BackfillSelfServeEligibleOnBillingSalesServePlanSubscriptions.new(args).run
end
