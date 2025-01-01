# typed: strict
# frozen_string_literal: true

module GitHub::Billing::CreditCard
  extend T::Sig

  # Public: The masked/formatted card number used in this transaction -
  #         the first digit, 11 asterisks, then the last four digits, formatted
  #         with spaces according to the card type.
  #
  # card_number - String of truncated card number (16 digits).
  # card_type   - String of card type (optional)
  #               If not presented, the card_number passed in must contain BIN
  #               (the first 6 digits) for #detect_card_type
  sig { params(card_number: String, card_type: T.nilable(String)).returns(String) }
  def format_card_number(card_number, card_type = nil)
    card_number = card_number.dup

    # Some saved truncated_number is ******
    return "" if card_number == "******" || card_number.blank?

    card_number = card_number.dup
    card_type ||= detect_card_type(card_number)

    if card_type == "American Express"
      card_number.sub!("******", "*****")
      pattern = [4, 6, 5]
    else
      pattern = [4, 4, 4, 4]
    end
    nums = []

    # Mask more digits for the ease of mind
    card_number[1..5] = "*****"

    pattern.each_with_index do |n, i|
      start = i - 1 >= 0 ? pattern[0..i - 1].to_a.inject(:+) : 0
      digits = card_number.slice(start..(start + n - 1))
      nums << digits
    end
    nums.join(" ")
  end

  # Public: The credit card type used in this transaction
  #
  # card_number - String of truncated card number or BIN.
  sig { params(card_number: String).returns(T.nilable(String)) }
  def detect_card_type(card_number)
    # NB- there's a comprehensive list of these at https://en.wikipedia.org/wiki/Payment_card_number
    case card_number
    when /\A(5[1-5]|2[2-7])/ then "MasterCard"
    when /\A4/ then "Visa"
    when /\A3(4|7)/ then "American Express"
    when /\A6011/ then "Discover"
    when /\A(30[0-5]|36|38)/ then "Diners Club"
    when /\A(3|2131|1800)/ then "JCB"
    end
  end

end
