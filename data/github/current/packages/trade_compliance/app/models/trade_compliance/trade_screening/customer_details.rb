# typed: strict
# frozen_string_literal: true

module TradeCompliance::TradeScreening
  # The customer details object that's required as part of building a request to the
  # Microsoft Trade Screening external service.
  class CustomerDetails

    sig { returns(T.nilable(String)) }
    attr_accessor :id
    sig { returns(T.nilable(String)) }
    attr_accessor :first_name
    sig { returns(T.nilable(String)) }
    attr_accessor :last_name
    sig { returns(T.nilable(String)) }
    attr_accessor :entity_name
    sig { returns(T.nilable(String)) }
    attr_accessor :vat_code
    sig { returns(T.nilable(String)) }
    attr_accessor :address1
    sig { returns(T.nilable(String)) }
    attr_accessor :address2
    sig { returns(T.nilable(String)) }
    attr_accessor :city
    sig { returns(T.nilable(String)) }
    attr_accessor :region
    sig { returns(T.nilable(String)) }
    attr_accessor :country_code
    sig { returns(T.nilable(String)) }
    attr_accessor :postal_code

    sig do
      params(
        id: T.nilable(String),
        first_name: T.nilable(String),
        last_name: T.nilable(String),
        entity_name: T.nilable(String),
        vat_code: T.nilable(String),
        address1: T.nilable(String),
        address2: T.nilable(String),
        city: T.nilable(String),
        region: T.nilable(String),
        country_code: T.nilable(String),
        postal_code: T.nilable(String)
      ).void
    end
    def initialize(id: nil, first_name: nil, last_name: nil, entity_name: nil, vat_code: nil, address1: nil, address2: nil, city: nil, region: nil, country_code: nil, postal_code: nil)
      @id = id
      @first_name = first_name
      @last_name = last_name
      @entity_name = entity_name
      @vat_code = vat_code
      @address1 = address1
      @address2 = address2
      @city = city
      @region = region
      @country_code = country_code
      @postal_code = postal_code
    end

    sig { params(account_type: AccountType).returns(T::Array[String]) }
    def validate(account_type:)
      errors = [
        validate_account_type(account_type: account_type),
      ]

      errors << add_attribute_name_to_error(name: "Id", error: validate_id)
      errors << add_attribute_name_to_error(name: "Address1", error: validate_address1)
      errors << add_attribute_name_to_error(name: "Address2", error: validate_address2)
      errors << add_attribute_name_to_error(name: "City", error: validate_city)
      errors << add_attribute_name_to_error(name: "Region", error: validate_region)
      errors << add_attribute_name_to_error(name: "Country code", error: validate_country_code)
      errors << add_attribute_name_to_error(name: "Postal code", error: validate_postal_code)
      errors.concat(validate_individual) if account_type == AccountType::Individual
      errors.concat(validate_business) if account_type == AccountType::Business

      errors.compact_blank
    end

    sig { params(account_type: AccountType).returns(T::Hash[Symbol, T.untyped]) }
    def to_hash(account_type:)
      errors = validate(account_type: account_type)
      raise CustomerDetailsError.new("id: #{id}, errors: #{errors.join(", ")}") if errors.any?

      first_name = self.first_name
      last_name = self.last_name
      first_name = last_name = nil unless account_type == AccountType::Individual
      {
        ReqID: id,
        FullName: full_name(account_type: account_type),
        FirstName: first_name,
        LastName: last_name,
        Addrs: {
          Addr: [
            {
              AdTyp: "C",
              Ad1: address1,
              Ad2: address2,
              Cty: city,
              Rgn: region,
              Pc: postal_code,
              Ctry: country_code,
            }.compact_blank,
          ],
        }.compact_blank,
      }.compact_blank
    end

    sig { returns(T.nilable(String)) }
    def validate_first_name
      min = 2
      max = 255
      return "can't be blank" if first_name.blank?
      return "is too short" if T.must(first_name).length < min

      return if T.must(first_name).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_last_name
      min = 2
      max = 255
      return "can't be blank" if last_name.blank?
      return "is too short" if T.must(last_name).length < min

      return if T.must(last_name).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_entity_name
      max = 800
      return "can't be blank" if entity_name.blank?
      return if T.must(entity_name).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_vat_code
      max = 50
      vat_invalid = vat_code.present? && T.must(vat_code).length > max
      return "is too long (maximum is #{max} characters)" if vat_invalid

      return unless ::TradeControls::Countries.vat_code_required_geo?(country_code)

      return "can't be blank" if vat_code.blank?
      return if T.must(vat_code).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_address1
      max = 128
      return "can't be blank" if address1.blank?
      return if T.must(address1).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_address2
      max = 128
      return if address2.blank?
      return if T.must(address2).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_city
      max = 170
      return "can't be blank" if city.blank?
      return if T.must(city).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_region
      max = 255
      region_invalid = region.present? && T.must(region).length > max
      return "is too long (maximum is #{max} characters)" if region_invalid

      return unless country_code.present?
      return unless country_code == "US" || country_code == "CA"

      "can't be blank" if region.blank?
    end


    sig { returns(T.nilable(String)) }
    def validate_country_code
      max = 2
      return "can't be blank" if country_code.blank?
      return if T.must(country_code).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { returns(T.nilable(String)) }
    def validate_postal_code
      max = 10
      return "is too long (maximum is #{max} characters)" if postal_code.present? && T.must(postal_code).length > max

      return unless ::TradeControls::Countries.postal_code_required_geo?(country_code)
      return "can't be blank" if postal_code.blank?
      return if T.must(postal_code).length <= max

      "is too long (maximum is #{max} characters)"
    end

    private

    sig { returns(T::Array[String]) }
    def validate_individual
      [
        add_attribute_name_to_error(name: "First name", error: validate_first_name),
        add_attribute_name_to_error(name: "Last name", error: validate_last_name),
      ].compact_blank
    end

    sig { returns(T::Array[String]) }
    def validate_business
      [
        add_attribute_name_to_error(name: "Entity name", error: validate_entity_name),
        add_attribute_name_to_error(name: "Vat code", error: validate_vat_code),
      ].compact_blank
    end

    sig { params(account_type: AccountType).returns(T.nilable(String)) }
    def validate_account_type(account_type:)
      return if account_type == AccountType::Individual || account_type == AccountType::Business

      "Account type can only be individual or business"
    end

    sig { returns(T.nilable(String)) }
    def validate_id
      max = 255
      return "can't be blank" if id.blank?
      return if T.must(id).length <= max

      "is too long (maximum is #{max} characters)"
    end

    sig { params(name: String, error: T.nilable(String)).returns(T.nilable(String)) }
    def add_attribute_name_to_error(name:, error:)
      return nil if error.blank?

      "#{name} #{error}"
    end

    sig { params(account_type: AccountType).returns(T.nilable(String)) }
    def full_name(account_type:)
      return "#{first_name}".rstrip + " #{last_name}".rstrip if account_type == AccountType::Individual

      "#{entity_name}".rstrip
    end
  end
end
