# typed: strict
# frozen_string_literal: true

module PaymentMethod::PaypalDependency
  extend ActiveSupport::Concern
  extend T::Sig
  extend T::Helpers

  requires_ancestor { PaymentMethod }

  included do
    T.bind(self, T.class_of(PaymentMethod))
    # Keep in sync with #paypal?
    scope :paypal, -> do
      where.not(paypal_email: nil)
        .where.not(payment_token: PaymentMethod::PAYMENT_TOKEN_CLEARED)
        .where("TRIM(#{table_name}.payment_token) <> ?", "")
        .where("TRIM(#{table_name}.paypal_email) <> ?", "")
    end
  end

  # Public: Email address associated with the PayPal account the user is using
  # to pay with. We cannot use this email for any other purposes and it doesn't
  # need to match the email we have on file for a user.
  # column :paypal_email

  # Public: Check if the payment method is PayPal.
  #
  # Keep in sync with the `paypal` scope.
  sig { returns(T::Boolean) }
  def paypal?
    !!(paypal_email.present? && valid_payment_token?)
  end
end
