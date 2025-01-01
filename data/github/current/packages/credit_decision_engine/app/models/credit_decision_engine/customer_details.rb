# typed: strict
# frozen_string_literal: true

# The customer details object that's required as part of building a request to the
# Microsoft CDE (Credit Decision Engine) live external service.
class CreditDecisionEngine::CustomerDetails
  extend T::Sig

  sig { returns(String) }
  attr_reader :name
  sig { returns(String) }
  attr_reader :address
  sig { returns(String) }
  attr_reader :city
  sig { returns(String) }
  attr_reader :country_code
  # optional fields
  sig { returns(T.nilable(String)) }
  attr_reader :postal_code
  sig { returns(T.nilable(String)) }
  attr_reader :state
  sig { returns(T.nilable(String)) }
  attr_reader :phone_number

  sig { params(name: String, address: String, city: String, country_code: String, postal_code: T.nilable(String), state: T.nilable(String), phone_number: T.nilable(String)).void }
  def initialize(name:, address:, city:, country_code:, postal_code: nil, state: nil, phone_number: nil)
    @name = name
    @address = address
    @city = city
    @country_code = country_code
    @postal_code = postal_code
    @state = state
    @phone_number = phone_number
  end

  sig { returns(T::Array[String]) }
  def validate
    [
      validate_name,
      validate_address,
      validate_city,
      validate_country_code,
      validate_postal_code,
      validate_state,
      validate_phone_number,
    ].compact_blank
  end

  sig { returns(T::Hash[Symbol, T.any(String, Float)]) }
  def to_hash
    {
      CustomerDetails: {
        Name: name,
        StreetAddress: address,
        City: city,
        PostalCode: postal_code,
        CountryCode: country_code,
        State: state,
        PhoneNumber: phone_number,
      }.compact_blank,
    }.compact_blank
  end

  private

  sig { returns(T.nilable(String)) }
  def validate_name
    return if name.present? && name.length <= 240

    "Name must be a string with a maximum of 240 characters"
  end

  sig { returns(T.nilable(String)) }
  def validate_address
    return if address.present? && address.length <= 70

    "Address must be a string with a maximum of 70 characters"
  end

  sig { returns(T.nilable(String)) }
  def validate_city
    return if city.present? && city.length <= 50

    "City must be a string with a maximum of 50 characters"
  end

  sig { returns(T.nilable(String)) }
  def validate_country_code
    return if country_code.present? && country_code.length <= 2

    "Country code must be a string with a maximum of 2 characters"
  end

  ########################################################################################
  # Optional value validations
  ########################################################################################

  sig { returns(T.nilable(String)) }
  def validate_postal_code
    return if postal_code.blank? || T.must(postal_code).length <= 10

    "Postal code must be a string with a maximum of 10 characters"
  end

  # State is an optional value. If it is provided, it must be a string with a maximum of 100 characters.
  # If the country code is US or CA, the state must be a valid state or province.
  sig { returns(T.nilable(String)) }
  def validate_state
    return if state.blank?

    state_value = T.must(state)
    return "State must be a string with a maximum of 100 characters" if state_value.length > 100

    return if country_code != "US" && country_code != "CA"

    state_exists = StatesAndProvinceHelper.find_state(state)
    "State must be a valid US state or CA province" unless state_exists
  end

  sig { returns(T.nilable(String)) }
  def validate_phone_number
    return if phone_number.blank? || T.must(phone_number).length <= 32

    "Phone number must be a string with a maximum of 32 characters"
  end
end
