# typed: strict
# frozen_string_literal: true

module TradeControls
  class UserHighRiskGeoManager
    include DomainFlagging
    extend T::Sig

    sig { params(location: T.nilable(T::Hash[Symbol, String]), email: T.nilable(String)).void }
    def initialize(location: nil, email: nil)
      @location = location
      @email = T.let(email.to_s, String)
    end

    sig { returns(T.nilable(String)) }
    def high_risk_geo
      if high_risk_inferred_country?(inferred_email_country)
        T.must(inferred_email_country).alpha3.presence || T.must(inferred_email_country).alpha2
      elsif high_risk_inferred_country?(inferred_ip_country)
        country_code = T.must(inferred_ip_country).alpha3.presence || T.must(inferred_ip_country).alpha2

        country_info = if inferred_region.present? && %w[UKR UA].include?(country_code)
          "#{country_code} -- #{Countries.ukraine_region_name(T.must(inferred_region))}"
        else
          country_code
        end
      end
    end

    private

    sig { returns(T.nilable(String)) }
    attr_reader :inferred_region

    sig { returns(T.nilable(TradeControls::Country)) }
    def inferred_email_country
      return if @email.blank?

      return @inferred_email_country if defined?(@inferred_email_country)

      @inferred_email_country = T.let(inferred_country, T.nilable(TradeControls::Country))
    end

    sig { returns(T.nilable(TradeControls::Country)) }
    def inferred_ip_country
      return if @location.blank?

      return @inferred_ip_country if defined?(@inferred_ip_country)

      country = Country.from_location(@location)
      @inferred_region = T.let(country.region_name, T.nilable(String))

      # Country.from_location does not return alpha3 but Country.from_braintree does
      @inferred_ip_country = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == country.alpha2 }), T.nilable(TradeControls::Country))
    end

    sig { params(ic: T.nilable(TradeControls::Country)).returns(T::Boolean) }
    def high_risk_inferred_country?(ic)
      return false if ic.blank? || ic.alpha2.blank?

      TradeControls::Countries.high_risk_geo?(country: T.must(ic.alpha2), region: inferred_region)
    end

    sig { override.returns(String) }
    def domain_field
      @email
    end

    sig { override.returns(Symbol) }
    def domain_field_type
      :email
    end
  end
end
