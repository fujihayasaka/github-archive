# typed: strict
# frozen_string_literal: true

# This class handles missing payment notification functionality for customers
# It tracks when customers have been notified about missing payment information
# and provides methods to retrieve this information.
class Customer::MissingPaymentNotification

  sig { params(customer: Customer).void }
  def initialize(customer)
    @customer = customer
  end

  # Get the key used to store the initial notification timestamp for missing payment
  sig { returns(String) }
  def key
    if customer.feature_flag_enabled?(:billing_cpwu_account_downgrade_roll_out, default: false)
      # Use the new key for customers with the feature enabled
      "customer:missing_payment_initial_notification_date:#{customer.id}"
    else
      # Use the old key for customers without the feature
      "customer:missing_payment_initial_notification:#{customer.id}"
    end
  end

  # Get the timestamp of when a customer was initially notified about missing payment information
  sig { returns(T.nilable(Time)) }
  def initially_notified_at
    value = Billing::Kv.store.get(key).value!
    return if value.nil?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end

  # Set the timestamp when a customer is notified about missing payment information
  sig { void }
  def set
    Billing::Kv.store.set(key, Time.now.utc.iso8601, expires: 3.months.from_now)
  end

  # Get the number of days since the customer was initially notified about missing payment
  sig { returns(Integer) }
  def days_since_initial_notification
    initial_notification = initially_notified_at
    return 0 if initial_notification.nil?

    (Time.now.utc.to_date - initial_notification.to_date).to_i
  end

  private

  sig { returns(Customer) }
  attr_reader :customer
end
