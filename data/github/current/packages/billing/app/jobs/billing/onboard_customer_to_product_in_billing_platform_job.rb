# typed: true
# frozen_string_literal: true

module Billing
  class OnboardCustomerToProductInBillingPlatformJob < BillingJob

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    retry_on StandardError

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

    sig { params(customer_id: Integer, products: T::Array[String], previous_customer_id: T.nilable(String)).void }
    def perform(customer_id:, products:, previous_customer_id: nil)
      @customer = Customer.find_by(id: customer_id)
      return unless @customer.present?
      return unless @customer.billable_owner.present?

      with_write do
        result = fix_billing_platform_rate_plan_charges
        unless result.success?
          raise StandardError.new("Failed to fix rate plan charges for customer #{customer.id} with error: #{result.error_message}")
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
            onboard_ghas
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
    end

    sig { void }
    def onboard_ghas
      entity = T.cast(T.must(customer).billable_owner, ::Billing::Types::Account)
      if entity.is_a?(User) && !entity.is_a?(Organization)
        # Individual users cannot currently be onboarded to GHAS
        return
      end

      mark_as_unbundled = entity.feature_enabled?(:unbundle_ghas_for_new_org_ent)
      if entity.organization?
        return unless entity.plan.business?

        mark_as_unbundled ||= entity.admins.any? { |actor| actor.feature_enabled?(:unbundle_ghas_for_new_org_ent) }
      end

      if mark_as_unbundled
        entity.set_customer_to_split_metered_offering(actor: User.ghost)
        entity.set_advanced_security_seats_for_entity(seats: 0, actor: User.ghost, is_stafftools_action: true)
        config.update!(ghas: true)
      elsif entity.business?
        # Old default behavior that can be removed once unbundle_ghas_for_new_org_ent is gone
        entity.mark_advanced_security_as_metered_for_entity(actor: User.ghost)
        entity.set_advanced_security_seats_for_entity(seats: 0, actor: User.ghost, is_stafftools_action: true)
        config.update!(ghas: true)
      end
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
      Billing::UpdateCustomerInBillingPlatformJob.perform_now(T.must(customer), previous_customer_id)
      config.update!(migration_date: DateTime.now) unless config.migration_date.present?
      config.update!(failed_at: nil) if config.failed_at.present?

      billable_owner = T.cast(T.must(customer).billable_owner, ::Billing::Types::Account)

      if billable_owner.is_a?(User) && billable_owner.feature_enabled?(:default_zero_budget_for_all_individuals_and_orgs)
        Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(T.must(customer), true) # set_zero_budget_limit
      elsif !customer.is_vnext_native?
        Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(T.must(customer))
      else
        if billable_owner.is_a?(Organization) && billable_owner.plan.free?
          Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(T.must(customer), true) # set_zero_budget_limit
        end

        if billable_owner.is_a?(User) && !billable_owner.is_a?(Organization)
          Billing::Migration::MigrateMeuseBudgetToBillingPlatformJob.perform_now(T.must(customer), true) # set_zero_budget_limit
        end
      end
    end
  end
end
