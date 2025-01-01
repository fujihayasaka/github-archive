# typed: strict
# frozen_string_literal: true

# Credit/debit card specific methods to be mixed into the PaymentMethod model.
module PaymentMethod::CreditCardDependency
  extend ActiveSupport::Concern
  extend T::Helpers

  requires_ancestor { PaymentMethod }

  include GitHub::Billing::CreditCard

  included do
    T.bind(self, T.class_of(PaymentMethod))

    # Keep in sync with #credit_card?
    scope :credit_cards, -> do
      where.not(truncated_number: nil)
        .where.not(payment_token: PaymentMethod::PAYMENT_TOKEN_CLEARED)
        .where("TRIM(#{table_name}.payment_token) <> ?", "")
        .where("TRIM(#{table_name}.truncated_number) <> ?", "")
    end
  end

  # Public: The truncated credit/debit card number, containing only the first six and last four
  # digits.
  # column :truncated_number
  # validates_presence_of :truncated_number

  # Public: Expiration date of the credit/debit card
  # column :expiration_month, :expiration_year
  # validates_presence_of :expiration_month, :expiration_year

  # Public: Brand of the credit/debit card. Can be "Visa", "MasterCard", "American Express",
  # "Diners Club", "JCB", or "Discover"
  # column :card_type
  # validates_presence_of :card_type

  # Public: Check if the payment method is a credit or debit card.
  #
  # Keep in sync with `credit_cards` scope.
  sig { returns(T::Boolean) }
  def credit_card?
    !!(truncated_number.present? && valid_payment_token?)
  end

  # Public: Last four digits of the credit/debit card number.
  sig { returns(T.nilable(String)) }
  def last_four
    return unless credit_card?

    truncated_number.to_s[-4..-1]
  end

  # Public: Updates the last four digits of the credit/debit card number.
  sig { params(new_last_4: String).void }
  def last_four=(new_last_4)
    self.truncated_number = "#{truncated_number.to_s[0...-4]}#{new_last_4}"
  end

  # Public: The first six digits of the credit/debit card number, also known as the Bank Identification
  # Number.
  sig { returns(T.nilable(String)) }
  def bank_identification_number
    return unless credit_card?

    truncated_number.to_s[0..5]
  end

  # Public: More masked version of the truncated_number that only contains the first number and
  # the last four, with asterisks in the middle.
  sig { returns(T.nilable(String)) }
  def formatted_number
    return unless credit_card?
    format_card_number truncated_number.to_s, card_type
  end

  # Public: Expiration date as a DateTime.
  sig { returns(T.nilable(DateTime)) }
  def expiration_date
    return unless expiration_month? && expiration_year?
    DateTime.parse(formatted_expiration_date)
  end

  # Public: Expiration date in M/YYYY format.
  sig { returns(String) }
  def formatted_expiration_date
    "#{expiration_month}/#{expiration_year}"
  end
end
