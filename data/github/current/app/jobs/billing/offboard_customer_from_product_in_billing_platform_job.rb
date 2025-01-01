# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: true
# frozen_string_literal: true

module Billing
  class OffboardCustomerFromProductInBillingPlatformJob < BillingJob

    retry_on_dirty_exit
    retry_on_recoverable_exceptions

    retry_on StandardError

    queue_as :billing_platform_customer_update

    sig { params(customer_id: Integer, product: String).void }
    def perform(customer_id:, product:)
      customer = Customer.find_by(id: customer_id)
      return if customer.nil?

      product_type = OnboardCustomerToProductInBillingPlatformJob::ProductEnum.from_serialized(product)

      with_write do
        config = BillingPlatformEnabledProduct.find_or_initialize_by(customer_id: customer.id)

        case product_type
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions
          offboard_actions(config: config)
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces
          offboard_codespaces(config: config)
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot
          offboard_copilot(config: config)
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas
          offboard_ghas(config: config)
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec
          config.update!(ghec: false)
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs
          offboard_git_lfs(config: config)
        when OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages
          config.update!(packages: false)
        else
          # This should not be reachable because every product type should be handled and enabled
          T.absurd(product) && Failbot.report(StandardError.new("Unhandled product type in #{self.class.name}"), { "gh.customer.id" => customer.id, "gh.product.name" => product })
        end

        customer.update!(billed_via_billing_platform: false) if config.reload.all_enabled_products.empty?
        Billing::UpdateCustomerInBillingPlatformJob.perform_later(T.must(customer))
      end
    end

    private

    sig { params(config: BillingPlatformEnabledProduct).void }
    def offboard_ghas(config:)
      config.update!(ghas: false)
      entity = T.cast(T.must(config.customer).billable_owner, T.any(Organization, Business))
      entity.mark_advanced_security_as_not_purchased_for_entity(actor: User.ghost)
    end

    sig { params(config: BillingPlatformEnabledProduct).void }
    def offboard_actions(config:)
      config.update!(actions: false)
      customer = T.must(config.customer)

      # Move CurrentUsage records effective_at for this customer to the next hour
      # so we don't emit for past and current hours to Meuse as it's already billed in Billing Platform
      billable_owner = T.must(customer.billable_owner)
      Billing::SharedStorage::CurrentUsage.where(billable_owner: billable_owner).update_all(effective_at: Time.current.beginning_of_hour + 1.hour)
    end

    def offboard_copilot(config:)
      config.update!(copilot: false)
      customer = T.must(config.customer)
    end

    def offboard_codespaces(config:)
      config.update!(codespaces: false)
    end

    def offboard_git_lfs(config:)
      config.update!(git_lfs: false)
    end
  end
end
