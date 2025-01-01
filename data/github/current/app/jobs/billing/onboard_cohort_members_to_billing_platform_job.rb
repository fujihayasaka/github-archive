# rubocop:todo GitHub/EnforcePackageAppStructure
# typed: strong
# frozen_string_literal: true

class Billing::OnboardCohortMembersToBillingPlatformJob < BillingJob
  retry_on_dirty_exit

  queue_as :billing_platform_onboard_customer

  sig { params(cohort_name: String).void }
  def perform(cohort_name:)
    customers = Customer.joins(:billing_platform_enabled_product).where(
      billing_platform_enabled_product: {
        cohort_name: cohort_name,
      },
    )

    customers.find_each do |customer|
      with_write do
        customer.onboard_to_billing_platform(
          products: [
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
            Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
          ]
        )
      end
    end
  end
end
