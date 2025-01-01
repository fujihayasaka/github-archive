# typed: true
# frozen_string_literal: true

module Billing
  class OnboardCustomerToProductInBillingPlatformJob < BillingJob

    DEFAULT_CONCURRENCY = 10

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    retry_on StandardError

    retry_on GitHub::Restraint::UnableToLock, wait: 10.seconds, jitter: 0.15, attempts: :unlimited do |_job, error|
      Failbot.report(error)
      GitHub.dogstats.increment(
        "billing.onboard_customer_to_product_in_billing_platform_job.lock_error",
      )
    end

    queue_as :billing_platform_onboard_customer

    locked_by timeout: ActiveJob::LockingJob::DEFAULT_LOCK_TIMEOUT, key: DEFAULT_LOCK_PROC

    class ProductEnum < T::Enum
      enums do
        Actions = new
        Codespaces = new
        Copilot = new
        Ghas = new
        Ghec = new
        Git_Lfs = new
        Packages = new
      end

      def self.serialized_enums
        values.map(&:serialize)
      end
    end

    resolve_tenant_context do |kwargs|
      customer = Customer.find(kwargs[:customer_id])
      customer.business
    rescue ActiveRecord::RecordNotFound
      GitHub.logger.error(
        "Failed to resolve tenant context.",
        "code.namespace": self.class.name&.underscore,
        "code.function": __method__,
        "gh.customer_id.id": kwargs[:customer_id],
      )
      raise
    end

    sig { params(customer_id: Integer, products: T::Array[String], previous_customer_id: T.nilable(String), unbundle_ghas: T.nilable(T::Boolean)).void }
    def perform(customer_id:, products:, previous_customer_id: nil, unbundle_ghas: nil)
      @customer = Customer.find_by(id: customer_id)
      return unless @customer.present?
      return unless @customer.billable_owner.present?

      max_concurrency = if FeatureFlag.vexi.enabled?(:onboarding_job_concurrency_level_5, default: false)
        DEFAULT_CONCURRENCY * 5 # 50 concurrent jobs
      elsif FeatureFlag.vexi.enabled?(:onboarding_job_concurrency_level_4, default: false)
        DEFAULT_CONCURRENCY * 4 # 40 concurrent jobs
      elsif FeatureFlag.vexi.enabled?(:onboarding_job_concurrency_level_3, default: false)
        DEFAULT_CONCURRENCY * 3 # 30 concurrent jobs
      elsif FeatureFlag.vexi.enabled?(:onboarding_job_concurrency_level_2, default: false)
        DEFAULT_CONCURRENCY * 2 # 20 concurrent jobs
      else
        DEFAULT_CONCURRENCY # 10 concurrent jobs
      end

      with_write do
        if FeatureFlag.vexi.enabled?(:use_concurrent_restraint_for_onboarding_job, default: false)
          restraint.lock!("OnboardCustomerToProductInBillingPlatformJob", max_concurrency, _ttl = 1.minute) do
            process(products: products, previous_customer_id: previous_customer_id, unbundle_ghas: unbundle_ghas)
          end
        else
          process(products: products, previous_customer_id: previous_customer_id, unbundle_ghas: unbundle_ghas)
        end
      end
    rescue => e
      with_write do
        config.update!(failed_at: Time.zone.now)
      end

      GitHub.dogstats.increment("billing_platform.onboard.error")
      exception_logging_context = {
        "code.namespace": "Billing::OnboardCustomerToProductInBillingPlatformJob",
        "gh.customer.id": customer_id,
        "exception.message": e.message,
      }
      GitHub.logger.error("Failed to onboard customer to billing platform", exception_logging_context)

      raise e
    end

    private

    sig { returns(Customer) }
    attr_reader :customer

    sig { params(products: T::Array[String], previous_customer_id: T.nilable(String), unbundle_ghas: T.nilable(T::Boolean)).void }
    def process(products:, previous_customer_id: nil, unbundle_ghas: nil)
      unless FeatureFlag.vexi.enabled_or_raise?(:skip_rate_plan_charge_fix_during_onboarding) # rubocop:disable GitHub/FeatureManagement/NoVexiEnabledOrRaiseUsage
        result = fix_billing_platform_rate_plan_charges
        unless result.success?
          raise StandardError.new("Failed to fix rate plan charges for customer #{customer.id} with error: #{result.error_message}")
        end
      end

      products.each do |product|
        begin
          product_type = ProductEnum.from_serialized(product)
        rescue KeyError
          Failbot.report(StandardError.new("Unhandled product type in #{self.class.name}"), { "gh.customer.id" => customer.id, "gh.product.name" => product })
          next
        end

        case product_type
        when ProductEnum::Actions
          onboard_actions
        when ProductEnum::Codespaces
          onboard_codespaces
        when ProductEnum::Copilot
          onboard_copilot
        when ProductEnum::Ghas
          onboard_ghas(unbundle_via_staff_input: unbundle_ghas)
        when ProductEnum::Ghec
          onboard_ghec
        when ProductEnum::Git_Lfs
          onboard_git_lfs
        when ProductEnum::Packages
          onboard_packages
        else
          T.absurd(product)
        end
      end

      onboard_customer(previous_customer_id)
    end

    sig { returns(GitHub::Billing::Result) }
    def fix_billing_platform_rate_plan_charges
      # Method aimed to rebuild rate plan charges that don't have 1st of the month bill cycle day.
      # New subscriptions are already created with the correct bill cycle day.
      # Follow https://github.com/github/gitcoin/issues/15472 for more information.

      # There's nothing to fix if the Zuora subscription is not present
      plan_subscription = T.must(customer).plan_subscription
      return GitHub::Billing::Result.success unless plan_subscription.present?
      zuora_subscription = plan_subscription.zuora_subscription
      return GitHub::Billing::Result.success unless zuora_subscription.present?

      billing_platform_charge_names = [
        "GitHub Actions Usage",
        "GitHub Advanced Security Usage",
        "GitHub Codespaces Usage",
        "GitHub Copilot Usage",
        "GitHub Enterprise Cloud Usage",
        "GitHub LFS Usage",
        "GitHub Package Registry Usage"
      ] # From https://data.githubapp.com/sql/share/295588d0

      rate_plan_changes = []

      zuora_subscription.active_rate_plans.each do |rate_plan|
        rate_plan.rate_plan_charges.each do |charge|
          # Charges with billingDay == "DefaultFromCustomer" should be converted to "SpecificDayofMonth/1st of the month"
          if billing_platform_charge_names.include?(charge["name"]) &&
            charge["price"] == 1.0 &&
            charge["billingDay"] == "DefaultFromCustomer"
            rate_plan_changes << {
              contractEffectiveDate: GitHub::Billing.today.to_s,
              ratePlanId: rate_plan["id"],
              newProductRatePlanId: rate_plan["productRatePlanId"],
              chargeOverrides: [{
                productRatePlanChargeId: charge["productRatePlanChargeId"],
                billCycleType: "SpecificDayofMonth",
                billingPeriodAlignment: "AlignToCharge",
                billCycleDay: 1
              }]
            }
          end
        end
      end

      # There's nothing to fix if no rate plan charges are found with "DefaultFromCustomer" billingDay
      return GitHub::Billing::Result.success unless rate_plan_changes.any?

      # The change array will remove the existing rate plan and reapply them with the chargeOverrides
      response = GitHub.zuorest_client.update_subscription(
        zuora_subscription.number, { change: rate_plan_changes },
        Billing::PlanSubscription::ZuoraSynchronizer::ZUORA_VERSION_HEADER
      )
      result = GitHub::Billing::Result.from_zuora(response)

      if result.success?
        # If this fails, the next subscription sync will attempt the update again
        plan_subscription.update_from_zuora_subscription
        result
      end

      result
    end

    sig { returns(BillingPlatformEnabledProduct) }
    def config
      BillingPlatformEnabledProduct.find_or_create_by!(customer_id: T.must(customer).id)
    end

    sig { void }
    def onboard_actions
      config.update!(actions: true)
    end

    sig { void }
    def onboard_codespaces
      config.update!(codespaces: true)
    end

    sig { void }
    def onboard_copilot
      config.update!(copilot: true)
    end

    sig { void }
    def onboard_git_lfs
      config.update!(git_lfs: true)

      entity = T.cast(T.must(customer).billable_owner, ::Billing::Types::Account)
      if entity.is_a?(User) || entity.is_a?(Organization)
        RebuildStorageUsageJob.perform_later(entity.id, { "notify" => false, "manual" => true })
      end
    end

    sig { params(unbundle_via_staff_input: T.nilable(T::Boolean)).void }
    def onboard_ghas(unbundle_via_staff_input: nil)
      # Always still onboard ghas
      config.update!(ghas: true)

      entity = T.cast(T.must(customer).billable_owner, ::Billing::Types::Account)
      if entity.is_a?(User) && !entity.is_a?(Organization)
        # Individual users cannot currently be onboarded to GHAS
        return
      end

      # This entity already has some kind of advanced security on it
      return if entity.advanced_security_purchased_for_entity?

      if entity.organization?
        # Organizations not on a 'business' / Teams plan are not supported
        return unless entity.plan.business?
      end

      # Default to giving unbundled security features
      mark_as_unbundled = true

      # Internally driven license model transitions may still require us to leave the customer
      # in a bundled state, so ensure input via API/stafftools is respected
      unless unbundle_via_staff_input.nil?
        mark_as_unbundled &&= unbundle_via_staff_input
      end

      if mark_as_unbundled
        entity.set_customer_to_split_metered_offering(actor: User.ghost)
      elsif entity.business?
        entity.mark_advanced_security_as_metered_for_entity(actor: User.ghost)
      end
      entity.set_advanced_security_seats_for_entity(seats: 0, actor: User.ghost, is_stafftools_action: true)
    rescue Configurable::AdvancedSecurityBillingConfig::SubscriptionQuantityCannotBeZero, Configurable::AdvancedSecurityBillingConfig::SubscriptionNotFoundError => e
      #  this failure shouldn't block onboarding
      GitHub.logger.error(
        "Failed to set advanced security seats to 0 for customer #{customer.id} with error: #{e.message}",
        "code.namespace": self.class.name&.underscore,
        "code.function": __method__,
        "gh.customer.id": customer.id,
        "gh.customer.billable_owner.id": entity&.id,
        "gh.customer.billable_owner.type": entity&.class&.name,
      )
    end

    sig { void }
    def onboard_ghec
      entity = T.cast(T.must(customer).billable_owner, T.any(User, Organization, Business))
      # Only businesses are onboarded to GHEC
      if entity.business?
        config.update!(ghec: true)
      end
    end

    sig { void }
    def onboard_packages
      config.update!(packages: true)
    end

    sig { params(previous_customer_id: T.nilable(String)).void }
    def onboard_customer(previous_customer_id = nil)
      customer.update_column(:billed_via_billing_platform, true)
      Billing::UpdateCustomerInBillingPlatformJob.perform_now(T.must(customer.reload), previous_customer_id)
      config.update!(migration_date: DateTime.now) unless config.migration_date.present?
      config.update!(failed_at: nil) if config.failed_at.present?

      billable_owner = T.cast(T.must(customer).billable_owner, ::Billing::Types::Account)

      return if billable_owner.feature_flag_enabled_or_raise?(:create_default_budgets_on_customer_upsert) # rubocop:disable GitHub/FeatureManagement/NoVexiActorFeatureFlagEnabledOrRaiseUsage

      if billable_owner.is_a?(User) || billable_owner.is_a?(Organization)
        Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(customer: T.must(customer), set_zero_budget_limit: true)
      elsif !customer.is_vnext_native?
        Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(customer: T.must(customer))
      elsif customer.billable_owner.is_a?(Business) && !T.cast(customer.billable_owner, Business).trial?
        Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(customer: T.must(customer), set_copilot_default_budget_only: true)
      end
    end

    sig { returns(GitHub::Restraint) }
    def restraint
      @restraint ||= GitHub::Restraint.new
    end
  end
end
