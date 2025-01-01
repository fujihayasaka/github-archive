# typed: strict
# frozen_string_literal: true

module Billing
  module Migration
    class MigrateMeuseBudgetToBillingPlatformJob < BillingJob
      include GitHub::Memoizer

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
        if FeatureFlag.vexi.enabled?(:billing_handle_customer_hash, default: false)
          customer[:customer]&.business
        else
          customer&.business
        end
      end

      sig { returns(T.nilable(T.any(User, Business))) }
      attr_reader :billable_owner

      sig { returns(T.nilable(Customer)) }
      attr_reader :customer

      sig { params(customer: Customer, set_zero_budget_limit: T::Boolean, set_copilot_default_budget_only: T::Boolean).void }
      def perform(customer:, set_zero_budget_limit: false, set_copilot_default_budget_only: false)
        @customer = T.let(customer, T.nilable(Customer))
        return unless customer.present?
        @billable_owner = T.let(customer.billable_owner, T.nilable(T.any(User, Business)))
        return unless billable_owner.present?

        budget_owner = T.must(billable_owner)
        shared_meuse_budget = budget_owner.budget_for(group: :shared)
        codespaces_meuse_budget = budget_owner.budget_for(group: :codespaces)

        restraint = GitHub::Restraint.new
        restraint.lock!("migrate-meuse-budget-to-vnext-#{customer.id}", _concurrency = 1, _ttl = 1.minute) do
          return if default_budget_already_created?(customer)
          return if customer_created_over_2_days_ago?(customer)
          return if customer_not_exists_in_billing_platform?(customer)
          return if customer_not_onboarded_to_billing_platform?(customer)
          return if customer_has_trade_restriction?(customer)
          if !set_copilot_default_budget_only
            return if customer_already_has_budget_in_billing_platform?(customer)
          end

          if should_create_copilot_budget?
            create_billing_platform_zero_limit_budget(customer, "SkuPricing", "copilot_premium_request")

            return if set_copilot_default_budget_only
          end

          if set_zero_budget_limit
            create_billing_platform_zero_limit_budget(customer, "ProductPricing", "git_lfs")
          else
            return if customer_has_no_payment_method?(customer)
          end

          create_billing_platform_budget(customer, shared_meuse_budget, "ProductPricing", "actions")
          create_billing_platform_budget(customer, shared_meuse_budget, "ProductPricing", "packages")
          create_billing_platform_budget(customer, codespaces_meuse_budget, "ProductPricing", "codespaces")

          set_budget_created(customer)
        end
      end

      sig { returns(T.nilable(T::Boolean)) }
      def should_create_copilot_budget?
        create_budget = billable_owner&.feature_flag_enabled?(:billing_create_zero_budget, default: false)

        overages_enabled = billable_owner&.feature_flag_enabled?(:billing_platform_overages_policies_enabled, default: false) && (billable_owner.is_a?(Business) || billable_owner.is_a?(Organization))

        return false if overages_enabled

        create_budget
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

      private

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_not_onboarded_to_billing_platform?(customer)
        return false if customer.billable_owner&.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if customer.billed_via_billing_platform?

        logger_and_metrics(customer, "skipped", "customer_not_onboarded", "Customer is not onboarded to billing platform")
        true
      end

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_not_exists_in_billing_platform?(customer)
        return false unless customer.billable_owner&.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        bp_customer = billing_client.get_customer(customer_id: customer.id)
        raise bp_customer if bp_customer.is_a?(Billing::Platform::Api::Error)
        return false if bp_customer.is_a?(Hash) && bp_customer[:customer].present?

        logger_and_metrics(customer, "skipped", "customer_not_exists", "Customer is not exists in billing platform")
        true
      end

      sig { params(customer: Customer).returns(T::Boolean) }
      def customer_created_over_2_days_ago?(customer)
        return false unless customer.billable_owner&.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return false if customer.created_at.after?(2.days.ago)

        logger_and_metrics(customer, "skipped", "customer_created_over_2_days_ago", "Customer created date is over 2 days ago")
        true
      end

      sig { params(customer: Customer).returns(T::Boolean) }
      def default_budget_already_created?(customer)
        return false unless customer.billable_owner&.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        return false unless Billing::Kv.store.exists(kv_key(customer)).value { false }

        logger_and_metrics(customer, "skipped", "default_budget_already_created", "Default budget already created for customer")
        true
      end

      sig { params(customer: Customer).void }
      def set_budget_created(customer)
        ActiveRecord::Base.connected_to(role: :writing) do
          Billing::Kv.store.set(kv_key(customer), "true", expires: 3.days.from_now)
        end
      end

      sig { params(customer: Customer).returns(String) }
      def kv_key(customer)
        "migrate_meuse_budget_to_billing_platform_job:#{customer.id}"
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
        return false if customer.billable_owner&.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

        budgets = billing_client.get_all_budgets(customer_id: customer.id)
        raise budgets if budgets.is_a?(Billing::Platform::Api::Error)
        return false if budgets[:budgets].empty?

        logger_and_metrics(customer, "skipped", "customer_already_has_budgets", "Customer already has budgets in billing platform")
        true
      end

      sig { params(customer: Customer, meuse_budget: ::Billing::Budget, pricing_target_type: String, pricing_target_id: String).void }
      def create_billing_platform_budget(customer, meuse_budget, pricing_target_type, pricing_target_id)
        return if skip_for_unlimited_spending?(customer, meuse_budget, pricing_target_id)
        return if skip_for_budget_already_exists?(customer, pricing_target_type, pricing_target_id)
        return if skip_for_zero_budget_for_new_businesses?(customer, meuse_budget, pricing_target_id)

        budget = upsert_budget_request_object(customer, meuse_budget, pricing_target_type, pricing_target_id)
        response = billing_client.create_or_update_budget(budget: budget.to_json)
        raise response if response.is_a?(Billing::Platform::Api::Error)

        instrument_budget_create(customer, budget)
      end

      sig { params(customer: Customer, pricing_target_type: String, pricing_target_id: String).void }
      def create_billing_platform_zero_limit_budget(customer, pricing_target_type, pricing_target_id)
        return if skip_for_budget_already_exists?(customer, pricing_target_type, pricing_target_id)

        new_zero_budget = ::Billing::Budget.new(spending_limit_in_subunits: 0, enforce_spending_limit: true, owner: customer.billable_owner)
        budget = upsert_budget_request_object(customer, new_zero_budget, pricing_target_type, pricing_target_id)
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

      sig { params(customer: Customer, pricing_target_type: String, pricing_target_id: String).returns(T::Boolean) }
      def skip_for_budget_already_exists?(customer, pricing_target_type, pricing_target_id)
        return false unless customer.billable_owner&.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage
        return false if existing_budgets.empty?

        budget_for_pricing_target_exists = existing_budgets.any? do |budget|
          budget.pricing_target_type == pricing_target_type &&
          budget.pricing_target_id == pricing_target_id
        end

        return false unless budget_for_pricing_target_exists

        logger_and_metrics(customer, "skipped", "budget_already_exists", "Budget already exists for #{pricing_target_type}:#{pricing_target_id}")
        true
      end

      sig { params(customer: Customer, meuse_budget: ::Billing::Budget, pricing_target_id: String).returns(T::Boolean) }
      def skip_for_zero_budget_for_new_businesses?(customer, meuse_budget, pricing_target_id)
        return false if customer.billable_owner.is_a?(User)
        return false if customer.billable_owner&.created_at <= Customer::BILLING_PLATFORM_GA_ROLLOUT_DATE # business was on Meuse before GA
        return false unless meuse_budget.spending_limit_in_subunits.zero?

        logger_and_metrics(customer, "skipped", "zero_budget_for_new_businesses", "Skipping zero budget for new business")
        true
      end

      sig { returns(T::Array[Billing::Platform::Api::Budget]) }
      memoize def existing_budgets
        budgets = billing_client.get_all_budgets(customer_id: customer&.id)
        raise budgets if budgets.is_a?(Billing::Platform::Api::Error)
        return [] unless budgets.is_a?(Hash) && budgets[:budgets].present?

        budgets[:budgets]
      end

      sig { params(customer: Customer, meuse_budget: ::Billing::Budget, pricing_target_type: String, pricing_target_id: String).returns Billing::Platform::Api::UpsertBudgetRequest }
      def upsert_budget_request_object(customer, meuse_budget, pricing_target_type, pricing_target_id)
        alert_recipients = billable_owner&.admins&.map(&:global_relay_id) || []
        budget_request = {
          targetAmount: (meuse_budget.spending_limit_in_subunits / 100).floor, # convert to dollars as spending limit is in cents
          targetType: "CustomerResource",
          targetId: customer.global_relay_id,
          pricingTargetType: pricing_target_type,
          pricingTargetId: pricing_target_id,
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
        event_payload = {
          actor: User.ghost,
          customer_id: customer.id.to_s,
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

        if billable_owner.is_a?(Organization)
          event_payload[:org] = billable_owner
        elsif billable_owner.is_a?(User)
          event_payload[:user] = billable_owner
        elsif billable_owner.is_a?(Business)
          event_payload[:business] = billable_owner
        end

        GitHub.instrument "billing.budget_create", event_payload

        logger_and_metrics(customer, "success", "budget_created", "Budget created in billing platform")
      end

      sig { returns(Billing::Platform::Api::Client) }
      def billing_client
        @_billing_client ||= T.let(Billing::Platform::Api::Client.new, T.nilable(Billing::Platform::Api::Client))
      end
    end
  end
end
