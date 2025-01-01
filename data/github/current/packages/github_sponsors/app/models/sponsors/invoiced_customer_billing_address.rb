# typed: true
# frozen_string_literal: true

# Public: A Plain Old Ruby Object (PORO) that represents the billing contact information for an invoiced customer
module Sponsors
  class InvoicedCustomerBillingAddress
    # billing_contact - A Sponsors::BillingContactResult that wraps the result of a Zuora request for billing
    #                   information for a specific customer.
    #                   https://www.zuora.com/developer/api-reference/#operation/Object_GETContact
    def initialize(billing_contact)
      @billing_contact = billing_contact
    end

    attr_reader :billing_contact

    def full_name
      return if first_name.blank? && last_name.blank?
      "#{first_name} #{last_name}"
    end

    def first_name
      return @first_name if defined?(@first_name)
      @first_name = customer_hash["FirstName"]&.strip
    end

    def last_name
      return @last_name if defined?(@last_name)
      @last_name = customer_hash["LastName"]&.strip
    end

    def street_address_1
      customer_hash["Address1"]
    end

    def street_address_2
      customer_hash["Address2"]
    end

    def city
      customer_hash["City"]
    end

    def region
      return StatesAndProvinceHelper.find_state(customer_hash["State"]) if country_is_united_states?
      customer_hash["State"]
    end

    def postal_code
      customer_hash["PostalCode"]
    end

    def country
      return @country if defined?(@country)
      @country = customer_hash["Country"]
    end

    private

    # Private: The data from Zuora about the contact's billing information
    #
    # Required keys: "FirstName", "LastName"
    # Optional keys: "Address1", "Address2", "City", "State", "PostalCode", "Country"
    #
    # Returns a Hash
    def customer_hash
      @customer_hash ||= billing_contact.contact_data || {}
    end

    def country_is_united_states?
      return false if country.nil?
      country_matches_united_states_string? || country_is_us_abbreviation?
    end

    def country_is_us_abbreviation?
      country_name_to_match.in?(%w(us usa))
    end

    def country_matches_united_states_string?
      country_name_to_match.include?("unitedstates")
    end

    # Private: Remove whitespace and periods from lowercase country name
    #
    # Used to ensure that "United States", "United States of America",
    # "US", "USA", "U.S.", and "U.S.A." are all valid variations of "United States"
    #
    # Returns String
    def country_name_to_match
      @country_name_to_match ||= country.downcase.gsub(/\s+/, "").delete(".")
    end
  end
end
