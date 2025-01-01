# typed: strict
# frozen_string_literal: true

class Billing::VatCode
  extend T::Sig

  sig { params(string: T.nilable(String)).returns(T.nilable(String)) }
  def self.parse(string)
    return unless string.present?

    # all digits
    if m = /(BG|CZ|DE|EE|EL|FI|HR|HU|IT|LT|LU|LV|MT|PL|PT|SE|SK)\s?\d{8,12}/.match(string) ||
           # characters
           /(CY|IE|NL)\s?[A-Z0-9]{8,12}/.match(string) ||
           # Austria - ATU99999999
           /AT\s?U[A-Z0-9]{8}/.match(string) ||
           # Belgium - BE0999999999
           /BE\s?0\d{9}/.match(string) ||
           # Spain - ESX9999999X
           /ES\s?[A-Z0-9]\d{7}[A-Z0-9]/.match(string) ||
           # Romania - RO99
           /RO\s?\d{2,10}/.match(string)

      strip_all_whitespace(m[0].to_s)
    # Denmark - DK99 99 99 99
    elsif m = /DK\s?(\d{8}|[\d\s]{11})/.match(string)
      stripped = strip_all_whitespace(m[0].to_s)
      [stripped[0, 4], stripped[4, 2], stripped[6, 2], stripped[8, 2]].join(" ")

    # United Kingdom - GB999 9999 99 999
    elsif m = /GB\s?([\d]{12}|[\d\s]{15})/.match(string)
      stripped = strip_all_whitespace(m[0].to_s)
      [stripped[0, 5], stripped[5, 4], stripped[9, 2], stripped[11, 3]].join(" ")

    # United Kingdom - GB999 9999 99
    elsif m = /GB\s?([\d]{9}|[\d\s]{11})/.match(string)
      stripped = strip_all_whitespace(m[0].to_s)
      [stripped[0, 5], stripped[5, 4], stripped[9, 2]].join(" ")

    # United Kingdom - GBHA999
    elsif m = /GB\s?[A-Z0-9]{5}/.match(string)
      strip_all_whitespace(m[0].to_s)

    # France - FRXX 999999999
    elsif m = /FR\s?[A-Z0-9]{2}\s?\d{9}/.match(string)
      stripped = strip_all_whitespace(m[0].to_s)
      [stripped[0, 4], stripped[4, 9]].join(" ")
    end
  end

  sig { params(string: String).returns(String) }
  def self.strip_all_whitespace(string)
    string.gsub(/\s+/, "")
  end
  private_class_method :strip_all_whitespace
end
