# typed: strict
# frozen_string_literal: true

class Businesses::Billing::PaymentInformationsController < Businesses::BillingsController
  before_action :business_access_required

  depends_on_clusters ApplicationRecord::Mysql1,
    ApplicationRecord::Configurations,
    ApplicationRecord::IamAbilities,
    ApplicationRecord::Mysql5,
    ApplicationRecord::Collab,
    ApplicationRecord::Mysql2,
    ApplicationRecord::NotificationsEntries,
    ApplicationRecord::Repositories,
    ApplicationRecord::Billing,
    ApplicationRecord::Copilot,
    only: [:show]
  before_action :add_paypal_csp_exceptions, only: [:show]

  javascript_bundle "billing-settings"

  sig { void }
  def show
    render "businesses/billing_platform/payment_information", locals: {
      business: this_business,
      show_azure_subscription_payment_information: show_azure_subscription_payment_information?,
    }
  end

  private

  sig { returns(T::Boolean) }
  def show_azure_subscription_payment_information?
    if this_business.metered_ghe?
      return true if this_business.linked_azure_subscription? || params[:show_subscriptions] == "true"
      false
    else
      this_business.billed_through_azure_subscription?
    end
  end

  sig { void }
  def add_paypal_csp_exceptions
    paypal_csp_exceptions = {
      img_src: [GitHub.paypal_checkout_url],
      connect_src: [GitHub.braintreegateway_url, GitHub.braintree_analytics_url]
    }

    SecureHeaders.append_content_security_policy_directives(request, paypal_csp_exceptions)
  end
end
