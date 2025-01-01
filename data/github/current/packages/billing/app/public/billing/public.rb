# typed: strict
# frozen_string_literal: true

module Billing
  module Public

    class BillingError < StandardError; end

    sig do
      params(
        street: String,
        city: String,
        region: String,
        postal_code: String,
        billing_country_code: String,
        currency_code: String,
      ).returns(AddressValidityResponse)
    end
    def self.validate_address(street:, city:, region:, postal_code:, billing_country_code: "US", currency_code: "USD")
      client = Taxamo::Client.new(private_token: GitHub.taxamo_api_private_token)
      result = client.address_lookup(street, city, region, postal_code, currency_code: currency_code, billing_country_code: billing_country_code)

      if result.no_match?
        if result.lookup_failed?
          return AddressValidityResponse.new(valid: false, error: "Something went wrong, please try again.")
        end
        return AddressValidityResponse.new(valid: false, error: "The address entered is invalid or cannot be found. Please make corrections and resave your billing information. Retrying with a 9-digit zip code may resolve the issue.")
      elsif result.suggested_match?
        # City or region mismatch is not a hard error since the postal code was able to be validated
        # We should still inform the user of the suggested city and region and ask them to confirm
        city_mismatch = result.suggested_city.to_s.downcase != city.to_s.downcase
        region_mismatch = result.suggested_region != region && result.suggested_region != StatesAndProvinceHelper.find_state(region)
        if city_mismatch || region_mismatch
          address_mismatch_error = "The address entered did not match the postal code. Did you mean #{result.suggested_city}, #{result.suggested_region}?"
          return AddressValidityResponse.new(valid: false, error: address_mismatch_error)
        end

        # Since both the region and city have been validated at this point,
        # we can use the suggested postal code to ensure we use the postal code + 4 if it was suggested
        if result.suggested_postal_code != postal_code
          return AddressValidityResponse.new(valid: true, suggested_postal_code: result.suggested_postal_code)
        end
      end

      AddressValidityResponse.new(valid: true)
    end

    # This method will blocklist a payment method for a given account
    #
    # account         - The account associated to the payment method to be blocklisted
    # payment_method  - The payment method to blocklist
    # reason          - A description indicating why this combination of an account + payment method is being blocklisted
    # consequence     - The consequence that will be executed if another account uses the same payment method
    # actor           - The actor calling this method
    # force           - When false, the reason + consequence of an existing (if applicable) blocklisted payment method entry will be applied. Set it to true to set a new reason and /or consequence.
    #
    sig do params(
      account: Types::Account,
      payment_method: PaymentMethod,
      reason: String,
      consequence: BlacklistedPaymentMethod::Consequence, # rubocop:disable Naming/InclusiveLanguage
      actor: User,
      force: T::Boolean,
    ).returns(BlacklistedPaymentMethod) # rubocop:disable Naming/InclusiveLanguage
    end
    def self.blocklist_payment_method(account:, payment_method:, reason:, consequence:, actor:, force: false)
      blocklisted_payment_methods = BlacklistedPaymentMethod.create_for_all_accounts(account, payment_method, reason:, consequence:, force:, actor:) # rubocop:disable Naming/InclusiveLanguage
      blocklisted_payment_method = T.must(blocklisted_payment_methods.first)
      blocklisted_payment_method.execute_consequence(include_all_accounts: true)

      blocklisted_payment_method
    end
  end
end
