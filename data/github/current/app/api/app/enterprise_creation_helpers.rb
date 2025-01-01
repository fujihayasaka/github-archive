# typed: true
# frozen_string_literal: true

module Api::App::EnterpriseCreationHelpers
  include Api::App::ErrorDependency

  private

  def create_emu_business_hash(params)
    ghec_seats = nil
    if params[:seats_plan_type] == "basic"
      ghec_seats = 0
    else
      ghec_seats = params[:seats].to_i
    end
    {
      name: params[:name],
      slug: params[:slug],
      shortcode: params[:shortcode],
      staff_owned: false,
      seats: ghec_seats,
      business_type: "enterprise_managed",
      seats_plan_type: params[:seats_plan_type],
      customer_attributes: { billing_end_date: params[:billing_end_date].to_time, name: params[:name], billing_type: "invoice", billing_attempts: 0, term_length: 12 },
      owners: []
    }
  end

  def onboard_to_billing_platform(business, azure_subscription_id = nil)
    GitHub.dogstats.increment("billing_platform.onboard_standalone_sales_serve_to_billing_platform")

    # Conditionally set the azure_subscription_id if present. This avoids potentially overwriting valid azure_subscription_ids with nil.
    if azure_subscription_id.present?
      T.must(business.customer).update!(metered_plan: true, azure_subscription_id: azure_subscription_id)
    else
      T.must(business.customer).update!(metered_plan: true)
    end

    business.customer.onboard_to_billing_platform(
      products: [
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Actions.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Codespaces.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Copilot.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Git_Lfs.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Packages.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghec.serialize,
        ::Billing::OnboardCustomerToProductInBillingPlatformJob::ProductEnum::Ghas.serialize
      ]
    )
  end

  def set_business_copilot_max_seats(business, params)
    if params[:seats_plan_type] == "basic" && params[:copilot_max_seats].present?
      copilot_max_seats = params[:copilot_max_seats].to_i
      business.copilot_max_seats = copilot_max_seats
    end
  end
end
