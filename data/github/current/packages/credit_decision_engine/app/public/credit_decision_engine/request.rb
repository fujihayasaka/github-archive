# typed: strict
# frozen_string_literal: true

# A Hash builder service used to generate the HTTP request body to communicate with
# Microsoft CDE (Credit Decision Engine) external service.
class CreditDecisionEngine::Request
  extend T::Sig

  sig do
    params(
      reference_id: String,
      customer_details: CreditDecisionEngine::CustomerDetails,
      currency_code: String,
      amount: Numeric,
      notes: T.nilable(String)
    )
    .returns(T::Hash[Symbol, T.untyped])
  end
  def self.build_request(reference_id:, customer_details:, currency_code:, amount:, notes: nil)
    # the CDE service only accepts amount of 15 digits and 2 decimals, we round so we can count the number of digits correctly
    amount = Float(amount.round(2))
    errors = [
      validate_reference_id(reference_id: reference_id),
      customer_details.validate,
      validate_currency_code(currency_code: currency_code),
      validate_amount(amount: amount),
      validate_notes(notes: notes),
    ].flatten!.compact_blank!

    raise CreditDecisionEngine::RequestError.new("Reference number: #{reference_id}, errors: #{errors.join(", ")}") if errors.any?

    customer_details.to_hash.merge({
      LobName: "GitHub",
      SourceReferenceID: reference_id,
      transactionCurrencyCode: currency_code,
      transactionCurrencyAmount: amount,
      AdditionalNotes: notes,
    }.compact_blank)
  end

  sig { params(reference_id: String).returns(T.nilable(String)) }
  private_class_method def self.validate_reference_id(reference_id:)
    return if reference_id.present? && reference_id.length <= 20

    "Reference ID must be a string with a maximum of 20 characters"
  end

  sig { params(currency_code: String).returns(T.nilable(String)) }
  private_class_method def self.validate_currency_code(currency_code:)
    return if currency_code.present? && currency_code.length <= 3

    "Currency code must be a string with a maximum of 3 characters"
  end

  sig { params(amount: Float).returns(T.nilable(String)) }
  private_class_method def self.validate_amount(amount:)
    return "Must provide a valid non-zero positive amount" if amount.blank? || amount <= 0

    return if (Math.log10(amount).to_i + 1) <= 13

    "Amount must be a decimal with a maximum of 13 digits"
  end

  sig { params(notes: T.nilable(String)).returns(T.nilable(String)) }
  private_class_method def self.validate_notes(notes:)
    return if notes.blank? || notes.length <= 1000

    "Notes must be a string with a maximum of 1000 characters"
  end
end
