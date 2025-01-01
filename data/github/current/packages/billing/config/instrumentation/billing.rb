# typed: strict
# frozen_string_literal: true

GitHub.subscribe(/\Abilling\.contact_(create|update)\Z/) do |_name, _start, _ending, _transaction_id, payload|
  account = if id = payload[:business_id]
    Business.new(id: id)
  elsif id = payload[:org_id]
    Organization.new(id: id)
  elsif id = payload[:user_id]
    User.new(id: id)
  end

  next unless account&.feature_enabled?(:billing_update_customer_in_stripe)

  Billing::UpdateCustomerInStripeJob.perform_later(payload[:customer_id])
end

GitHub.subscribe(/\Apayment_method\.(create|update)\Z/) do |_name, _start, _ending, _transaction_id, payload|
  account = if id = payload[:business_id]
    Business.new(id: id)
  elsif id = payload[:org_id]
    Organization.new(id: id)
  elsif id = payload[:user_id]
    User.new(id: id)
  end

  next unless account&.feature_enabled?(:billing_update_payment_method_in_stripe)
  next unless payload[:payment_method] == "card"

  Billing::UpdatePaymentMethodInStripeJob.perform_later(payload[:payment_method_id])
end
