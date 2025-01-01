# typed: strict
# frozen_string_literal: true

module TradeControls
  # Represents a collection of Country instances.
  #
  # If/when Country becomes a db-backed ActiveRecord model, the majority of
  # the Countries interface would become class methods and/or scopes on Country.
  # Thus the api of this class is expected to be similar to (and compatible with)
  # the majority of the AR Relation interface (ie, enumerable, finders, plucking)
  class Countries
    include LocationTraits
    extend T::Sig
    extend T::Generic

    CUBA = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == "CU" }), TradeControls::Country)
    SYRIA = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == "SY" }), TradeControls::Country)
    NORTH_KOREA = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == "KP" }), TradeControls::Country)
    IRAN = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == "IR" }), TradeControls::Country)
    BELARUS = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == "BY" }), TradeControls::Country)
    WESTERN_SAHARA = T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == "EH" }), TradeControls::Country)

    CRIMEA = T.let(Country.from_braintree(UKRAINE_BRAINTREE_COUNTRY)
      .update(region: { name: "Crimea", code: "43" }), TradeControls::Country)
    LUHANSK = T.let(Country.from_braintree(UKRAINE_BRAINTREE_COUNTRY)
      .update(region: { name: "Luhansk", code: "09" }), TradeControls::Country)
    DONETSK_OBLAST = T.let(Country.from_braintree(UKRAINE_BRAINTREE_COUNTRY)
      .update(region: { name: "Donetsk Oblast", code: "14" }), TradeControls::Country)

    RUSSIA_BRAINTREE_COUNTRY = T.let(Braintree::Address::CountryNames.find { |c| c[1] == "RU" }, T::Array[String])
    RUSSIA = T.let(Country.from_braintree(RUSSIA_BRAINTREE_COUNTRY), TradeControls::Country)

    COPILOT_AUTH_BLOCKED_COUNTRY_LIST = T.let([
      BELARUS,
      CUBA,
      IRAN,
      NORTH_KOREA,
      RUSSIA,
      SYRIA
    ].freeze, T::Array[TradeControls::Country])

    COPILOT_VNEXT_AUTH_BLOCKED_COUNTRY_LIST = T.let([
      BELARUS,
      CUBA,
      NORTH_KOREA,
      RUSSIA,
      SYRIA
    ].freeze, T::Array[TradeControls::Country])

    COPILOT_AUTH_BLOCKED_REGION_LIST = T.let([
      CRIMEA,
      DONETSK_OBLAST,
      LUHANSK,
    ], T::Array[TradeControls::Country])

    VAT_CODE_REQUIRED_GEOS = T.let(%w[
      AM AZ BY BR CN HU IN IQ KZ KG MD MM PL
      RU SA ZA SS TJ TH TR UA AE UZ VE VN
    ].to_set.freeze, T::Set[String])

    POSTAL_CODE_REQUIRED_GEOS = T.let(%w[UA US RU], T::Array[String])

    # For checking lic_r compliance for organizations.
    ORG_COMPLIANCE_ROLLOUT = T.let(%w[
      RU BY
    ].to_set.freeze, T::Set[String])

    include Enumerable
    delegate :each, to: :@countries

    Elem = type_member { { fixed: TradeControls::Country } }

    sig { params(countries: T::Array[TradeControls::Country]).void }
    def initialize(countries)
      @countries = T.let(Set.new(countries), T::Set[TradeControls::Country])
    end

    # These "property" methods are just shortcuts for mapping out particular
    # properties from the contained Country instances. If Country becomes an
    # AR model, these would just become "plucks"
    sig { returns(T::Array[T.nilable(String)]) }
    def alpha2
      map(&:alpha2)
    end

    sig { returns(T::Array[T.nilable(String)]) }
    def alpha3
      map(&:alpha3)
    end

    sig { returns(T::Array[T.nilable(String)]) }
    def domain
      map(&:domain)
    end

    sig { returns(T::Array[T.nilable(String)]) }
    def name
      map(&:name)
    end

    sig { returns(T::Array[T.nilable(String)]) }
    def region_name_downcase
      map(&:region_name).compact.map(&:downcase)
    end

    # This is intentionally similar AR finders because Country may very likely
    # become an AR model and thus have a find_by class method.
    sig { params(attributes: T.untyped).returns(T::Array[TradeControls::Country]) }
    def where(**attributes)
      find_all do |c|
        attributes.all? do |k, v|
          Array(v).include? c.__send__(k)
        end
      end
    end

    # This is intentionally similar AR finders because Country may very likely
    # become an AR model and thus have a find_by class method.
    sig { params(attributes: T.untyped).returns(T.nilable(TradeControls::Country)) }
    def find_by(**attributes) # rubocop:disable GitHub/FindByDef
      where(**attributes).first
    end

    # These constants would likely be scopes for pre-set groups of countries,
    # if Country were an AR model.
    BILLING_ADDRESS_DENYLIST = T.let(new([CUBA, NORTH_KOREA, SYRIA]), TradeControls::Countries)
    SANCTIONED = T.let(new([NORTH_KOREA, SYRIA]), TradeControls::Countries)
    SANCTIONED_REGIONS = T.let(new([CRIMEA]), TradeControls::Countries)
    HIGH_RISK_GEOS = T.let(new([IRAN]), TradeControls::Countries)
    HIGH_RISK_GEOS_COUNTRY_LIST = T.let(new([NORTH_KOREA, SYRIA, IRAN, BELARUS]), TradeControls::Countries)
    # This is used only for flagging high risk regions as opposed to enforcing restrictions
    HIGH_RISK_FLAGGABLE_REGIONS_LIST = T.let(new([CRIMEA, LUHANSK, DONETSK_OBLAST]), TradeControls::Countries)

    REGIONS_WITH_CITY_ENFORCEMENT = T.let(new([LUHANSK, DONETSK_OBLAST]), TradeControls::Countries)

    MARKETING_BLOCKED_COUNTRY_LIST = T.let(new([WESTERN_SAHARA, RUSSIA]), TradeControls::Countries)

    # This would be a scope+pluck if Country were an AR model
    sig { returns(T::Array[T.nilable(String)]) }
    def self.billing_address_blacklist_alpha3
      @billing_address_blacklist_alpha3 ||= T.let(BILLING_ADDRESS_DENYLIST.alpha3, T.nilable(T::Array[T.nilable(String)]))
    end

    # This would be a scope if Country were an AR model
    sig { returns(T::Array[T::Array[String]]) }
    def self.currently_unsanctioned
      @currently_unsanctioned ||=
      T.let(Braintree::Address::CountryNames.reject do |(_, _, alpha3, _)|
        billing_address_blacklist_alpha3.include?(alpha3.upcase)
      end, T.nilable(T::Array[T::Array[String]]))
    end

    # wrapper around set of high risk geo locations
    sig { returns(TradeControls::Countries) }
    def self.high_risk_geos
      HIGH_RISK_GEOS
    end

    sig { params(actor: Billing::Types::Account).returns(T::Array[TradeControls::Country]) }
    def self.copilot_auth_blocked_countries(actor:)
      return COPILOT_VNEXT_AUTH_BLOCKED_COUNTRY_LIST if actor.feature_enabled?(:sdn_copilot_vnext)

      COPILOT_AUTH_BLOCKED_COUNTRY_LIST
    end

    sig { returns(T::Array[T::Array[String]]) }
    def self.marketing_targeted_countries
      currently_unsanctioned.reject { |_, _, alpha3, _| MARKETING_BLOCKED_COUNTRY_LIST.alpha3.include?(alpha3&.upcase) }
    end

    # Public: Checks if a particular region or city can be flagged as high risk.
    #
    # Returns Boolean
    sig { params(country: String, region: T.nilable(String), city: T.nilable(String)).returns(T::Boolean) }
    def self.high_risk_region_or_city?(country:, region: nil, city: nil)
      return false if region.blank?

      city = City.new(alpha2: country, city: city, region: { name: region })
      return true if city.high_risk?

      HIGH_RISK_FLAGGABLE_REGIONS_LIST.region_name_downcase.include?(region.downcase)
    end

    # Public: used to return a short version of Ukraine region name
    #
    # Returns String
    sig { params(region_name: String).returns(String) }
    def self.ukraine_region_name(region_name)
      if "Luhansk".casecmp(region_name)&.zero?
        "LNR"
      elsif "Donetsk Oblast".casecmp(region_name)&.zero?
        "DNR"
      elsif "Crimea".casecmp(region_name)&.zero?
        "Crimea"
      else
        "Unknown"
      end
    end

    # Public: Checks if a particular country or region is high risk.
    #
    # This is used for flagging (recording the geo information) purposes only
    # and is not for enforcing restrictions.
    #
    # This is a temporary solution as sanctioned list and SDN high risk
    # countries and regions currently isn't the same. They will be in the future,
    # however for now this method merges the two.
    #
    # Returns Boolean
    sig { params(country: String, region: T.nilable(String), city: T.nilable(String)).returns(T::Boolean) }
    def self.high_risk_geo?(country:, region: nil, city: nil)
      return true if HIGH_RISK_GEOS_COUNTRY_LIST.alpha2.include?(country)

      self.high_risk_region_or_city?(country: country, region: region, city: city)
    end

    sig { params(country_code: T.nilable(String)).returns(T::Boolean) }
    def self.vat_code_required_geo?(country_code)
      return false if country_code.blank?

      VAT_CODE_REQUIRED_GEOS.include?(country_code)
    end

    sig { params(country_code: T.nilable(String)).returns(T::Boolean) }
    def self.postal_code_required_geo?(country_code)
      return false if country_code.blank?

      POSTAL_CODE_REQUIRED_GEOS.include?(country_code)
    end
  end
end
