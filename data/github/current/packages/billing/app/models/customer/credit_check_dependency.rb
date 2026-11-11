# typed: strict
# frozen_string_literal: true

module Customer::CreditCheckDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { Customer }

  included do
    T.bind(self, T.class_of(Customer))

    has_one :credit_check, class_name: "Billing::CreditCheck", dependent: :destroy
  end

  sig { params(reference_id: String, customer_details: CreditDecisionEngine::CustomerDetails, currency_code: String, amount: Numeric).void }
  def request_credit_check(reference_id:, customer_details:, currency_code:, amount:)
    customer_id = self.id
    response = CreditDecisionEngine::Client.request_credit_check(reference_id: reference_id, customer_details: customer_details, currency_code: currency_code, amount: amount)

    credit_check = Billing::CreditCheck.find_or_initialize_by(customer_id: customer_id)
    credit_check.update!(status: response.status, request_id: response.request_id)
  end
end
