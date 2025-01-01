# typed: true
# frozen_string_literal: true

# This job runs every day and checks that
# azure subscription IDs for customers signed up with an Enterprise Agreement
# are valid and can be billed.
# If not, it will notify SalesOps
module Billing
  module Azure
    class CheckAzureSubscriptionsJob < ApplicationJob

      queue_as :billing

      schedule interval: 1.day, condition: -> { GitHub.billing_enabled? }

      exempt_from_tenant_context_requirement

      def perform
        http_client = GitHub::Azure::HttpClient.new
        subscription_client = Billing::Azure::SubscriptionClient.new(http_client: http_client)
        invalid_accounts = []

        azure_billed_businesses.each do |business|
          # Collect all of the EA accounts that have invalid subscrption ids.
          subscription_status = ActiveRecord::Base.connected_to(role: :writing) do
            subscription_client.subscription_exists?(subscription_id: business.customer.azure_subscription_id)
          end
          invalid_accounts.push(business) unless subscription_status[:exists]
        end

        (metered_via_azure_customers + metered_plan_customers).uniq.each do |customer|
          subscription_status = ActiveRecord::Base.connected_to(role: :writing) do
            subscription_client.subscription_exists?(subscription_id: customer.azure_subscription_id)
          end
          invalid_accounts.push(customer.billable_owner) unless subscription_status[:exists]
        end

        # Unique result from MS Paper + Metered via Azure + Metered plan customers
        invalid_accounts = invalid_accounts.compact.uniq unless invalid_accounts.empty?

        GitHub.dogstats.gauge("billing.azure.invalid_subscription_ids", invalid_accounts.count)

        notify_invalid_accounts(invalid_accounts) unless invalid_accounts.empty?
      end

      private

      def azure_billed_businesses
        return @azure_billed_businesses if defined?(@azure_billed_businesses)
        @azure_billed_businesses = Business.with_active_azure_subscription.not_staff_owned
      end

      def metered_via_azure_customers
        return @metered_via_azure_customers if defined?(@metered_via_azure_customers)
        @metered_via_azure_customers = Customer.where.not(azure_subscription_id: nil).where(metered_via_azure: true)
      end

      def metered_plan_customers
        return @metered_plan_customers if defined?(@metered_plan_customers)
        @metered_plan_customers = Customer.where.not(azure_subscription_id: nil).where(metered_ghe: true)
      end

      def notify_invalid_accounts(invalid_accounts)
        notifier = Billing::Azure::InvalidSubscriptionNotifier.new
        invalid_accounts.each do |invalid_account|
          begin
            invalid_account.customer.instrument("invalid_azure_subscription_detected")
            if invalid_account.business?
              notifier.notify(business: invalid_account)
            elsif invalid_account.organization? && invalid_account.invoiced?
              notifier.notify(org: invalid_account)
            else
              disable_metered_via_azure_and_set_notification_key(invalid_account)
            end
          rescue Exception => ex # rubocop:todo Lint/GenericRescue
            GitHub.dogstats.increment("billing.subscriptions.invalid_subscription_notifier_failure", tags: ["error:#{ex.class}"])
            next
          end
        end
      end

      def disable_metered_via_azure_and_set_notification_key(invalid_account)
        return unless invalid_account.organization?
        return if invalid_account.invoiced?
        ActiveRecord::Base.connected_to(role: :writing) do
          customer = invalid_account.customer
          customer.update(metered_via_azure: false)
          # This is used to display a banner on the customer's billing page
          Billing::Kv.store.set(customer.invalid_azure_subscription_id_key, "true", expires: invalid_account.next_metered_billing_cycle_starts_at)
        end
      end
    end
  end
end
