# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strict
# frozen_string_literal: true

module Billing
  module Migration
    class MigrateMeuseBudgetToBillingPlatformJob < BillingJob
      retry_on_dirty_exit
      retry_on_recoverable_exceptions

      retry_on StandardError
      retry_on GitHub::Restraint::UnableToLock, wait: 30.seconds, attempts: 5

      RETRYABLE_ERRORS = T.let(
        [
          Net::OpenTimeout,
          Net::ReadTimeout,
          Billing::Platform::Api::Error,
        ].freeze,
        T::Array[Object],
      )

      RETRYABLE_ERRORS.each do |error_class|
        retry_on error_class do |job, error|
          job.logger_and_metrics(job.customer, "failed", error.class.name.underscore.parameterize, error.message)
          Failbot.report(error, job: self, customer: job.customer, billable_owner: job.billable_owner)
        end
      end

      resolve_tenant_context do |customer|
        customer&.business
      end

      sig { params(customer: Customer, set_zero_budget_limit: T::Boolean).void }
      def perform(customer, set_zero_budget_limit = false)
        @customer = T.let(customer, T.nilable(Customer))
        return unless customer.present?
        @billable_owner = T.let(customer.billable_owner, T.nilable(T.any(User, Business)))
        return unless billable_owner.present?

        budget_owner = T.must(billable_owner)
        shared_meuse_budget = budget_owner.budget_for(group: :shared)
        codespaces_meuse_budget = budget_owner.budget_for(group: :codespaces)

        restraint = GitHub::Restraint.new
        restraint.lock!("migrate-meuse-budget-to-vnext-#{customer.id}", _concurrency = 1, _ttl = 1.minute) do
          return if customer_not_onboarded_to_billing_platform?(customer)
          return if customer_has_trade_restriction?(customer)
          return if customer_already_has_budget_in_billing_platform?(customer)

          if set_zero_budget_limit
            create_billing_platform_zero_limit_budget(customer, "git_lfs")
          else
            return if customer_has_no_payment_method?(customer)
          end

          create_billing_platform_budget(customer, shared_meuse_budget, "actions")
          create_billing_platform_budget(customer, shared_meuse_budget, "packages")
          create_billing_platform_budget(customer, codespaces_meuse_budget, "codespaces")
        end
      end

      private

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_not_onboarded_to_billing_platform?(customer)
        return false if customer.billed_via_billing_platform?

        logger_and_metrics(customer, "skipped", "customer_not_onboarded", "Customer is not onboarded to billing platform")
        true
      end

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_has_no_payment_method?(customer)
        return false if customer.billable_owner&.has_valid_payment_method?(feature_type: :noncommercial)
        return false if customer.billable_owner&.invoiced?

        logger_and_metrics(customer, "skipped", "no_payment_method", "Customer has no payment method")
        true
      end

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_has_trade_restriction?(customer)
        restricted = customer.billable_owner&.has_any_trade_restrictions? ||
          customer.billable_owner&.has_commercial_interaction_restriction?(feature_type: :cost_management)

        return false unless restricted

        logger_and_metrics(customer, "skipped", "trade_restricted_customer", "Customer with trade restriction can't create budget")
        true
      end

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_already_has_budget_in_billing_platform?(customer)
        budgets = billing_client.get_all_budgets(customer_id: customer.id)
        raise budgets if budgets.is_a?(Billing::Platform::Api::Error)
        return false if budgets[:budgets].empty?

        logger_and_metrics(customer, "skipped", "customer_already_has_budgets", "Customer already has budgets in billing platform")
        true
      end

      sig { params(customer: Customer, meuse_budget: ::Billing::Budget, product: String).void }
      def create_billing_platform_budget(customer, meuse_budget, product)
        return if skip_for_unlimited_spending?(customer, meuse_budget, product)

        budget = upsert_budget_request_object(customer, meuse_budget, product)
        response = billing_client.create_or_update_budget(budget: budget.to_json)
        raise response if response.is_a?(Billing::Platform::Api::Error)

        instrument_budget_create(customer, budget)
      end

      sig { params(customer: Customer, product: String).void }
      def create_billing_platform_zero_limit_budget(customer, product)
        new_zero_budget = ::Billing::Budget.new(spending_limit_in_subunits: 0, enforce_spending_limit: true, owner: customer.billable_owner)
        budget = upsert_budget_request_object(customer, new_zero_budget, product)
        response = billing_client.create_or_update_budget(budget: budget.to_json)

        raise response if response.is_a?(Billing::Platform::Api::Error)

        instrument_budget_create(customer, budget)
      end

      sig { params(customer: Customer, meuse_budget: ::Billing::Budget, product: String).returns(T::Boolean) }
      def skip_for_unlimited_spending?(customer, meuse_budget, product)
        return false unless meuse_budget.unlimited_spending_limit?

        logger_and_metrics(customer, "skipped", "unlimited_spending_limit", "Customer has unlimited Meuse budget for #{product}")
        true
      end

      sig { params(customer: Customer, meuse_budget: ::Billing::Budget, product: String).returns Billing::Platform::Api::UpsertBudgetRequest }
      def upsert_budget_request_object(customer, meuse_budget, product)
        alert_recipients = billable_owner&.admins&.map(&:global_relay_id) || []
        budget_request = {
          targetAmount: (meuse_budget.spending_limit_in_subunits / 100).floor, # convert to dollars as spending limit is in cents
          targetType: "CustomerResource",
          targetId: customer.global_relay_id,
          pricingTargetType: "ProductPricing",
          pricingTargetId: product,
          budgetLimitType: "PreventFurtherUsage",
          alertEnabled: meuse_budget.paid_usage_notification && alert_recipients.any?,
          alertRecipientUserIds: alert_recipients,
        }

        Billing::Platform::Api::UpsertBudgetRequest.new(
          raw_upsert_budget_request: budget_request,
          current_user: User.ghost,
          customer_id: customer.id.to_s,
          this_entity: billable_owner,
        )
      end

      sig { params(customer: Customer, budget: Billing::Platform::Api::UpsertBudgetRequest).void }
      def instrument_budget_create(customer, budget)
        GitHub.instrument "billing.budget_create", {
          actor: User.ghost,
          customer_id: customer.id.to_s,
          business: billable_owner,
          target_amount: budget.target_amount,
          target_type: budget.target_type,
          target_id: budget.target_id,
          alert_enabled: budget.alert_enabled?,
          pricing_target_type: budget.pricing_target_type,
          pricing_target_id: budget.pricing_target_id,
          budget_limit_type: budget.budget_limit_type,
          alert_recipient_user_ids: budget.alert_recipient_user_ids,
          automatic_migration_from_meuse: true,
          status: "success"
        }

        logger_and_metrics(customer, "success", "budget_created", "Budget created in billing platform")
      end

      sig { params(customer: Customer, status: String, reason: String, message: String).void }
      def logger_and_metrics(customer, status, reason, message)
        GitHub.logger.info(
          message,
          "code.namespace": self.class.name&.underscore,
          "code.function": __method__,
          "gh.customer.id": customer.id,
          "gh.customer.billed_via_billing_platform": customer.billed_via_billing_platform?,
          "code.namespace.reason": reason,
          "code.completion.status": status,
        )

        GitHub.dogstats.increment(
          "billing.migrate_meuse_budget_to_billing_platform_job.done",
          tags: ["status:#{status}", "reason:#{reason}"],
        )
      end

      sig { returns(Billing::Platform::Api::Client) }
      def billing_client
        @_billing_client ||= T.let(Billing::Platform::Api::Client.new, T.nilable(Billing::Platform::Api::Client))
      end

      sig { returns(T.nilable(T.any(User, Business))) }
      attr_reader :billable_owner

      sig { returns(T.nilable(Customer)) }
      attr_reader :customer
    end
  end
end
