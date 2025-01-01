# typed: strict
# frozen_string_literal: true

# This module handles missing payment notification functionality for customers
# It tracks when customers have been notified about missing payment information
# and provides methods to retrieve this information.
module Customer::MissingPaymentNotificationDependency
  extend T::Helpers

  # Tell Sorbet that this module will be included in Customer class
  requires_ancestor { Customer }

  # Get the key used to store the initial notification timestamp for missing payment
  sig { returns(String) }
  def missing_payment_initial_notification_key
    if self.feature_enabled?(:billing_cpwu_account_downgrade_roll_out)
      # Use the new key for customers with the feature enabled
      "customer:missing_payment_initial_notification_date:#{id}"
    else
      # Use the old key for customers without the feature
      "customer:missing_payment_initial_notification:#{id}"
    end
  end

  # Get the timestamp of when a customer was initially notified about missing payment information
  sig { returns(T.nilable(Time)) }
  def missing_payment_initial_notification
    value = Billing::Kv.store.get(missing_payment_initial_notification_key).value!
    return if value.nil?

    Time.iso8601(value)
  rescue ArgumentError
    nil
  end

  # Set the timestamp when a customer is notified about missing payment information
  sig { void }
  def set_missing_payment_initial_notification
    Billing::Kv.store.set(missing_payment_initial_notification_key, Time.now.utc.iso8601, expires: 3.months.from_now)
  end

  # Get the number of days since the customer was initially notified about missing payment
  sig { returns(Integer) }
  def days_since_missing_payment_initial_notification
    initial_notification = missing_payment_initial_notification
    return 0 if initial_notification.nil?

    (Time.now.utc.to_date - initial_notification.to_date).to_i
  end
end
