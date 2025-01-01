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
    EU_COUNTRIES = T.let(%w[AT BE BG HR CY CZ DK EE FI FR DE GR HU IE IT LV LT LU MT NL PL PT RO SK SI ES SE], T::Array[String])

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
    SANCTIONED_REGIONS = T.let(new([CRIMEA]), TradeControls::Countries)
    # This is used only for flagging high risk regions as opposed to enforcing restrictions
    HIGH_RISK_GEOS = T.let(new([IRAN, SYRIA]), TradeControls::Countries)
    GHES_BLOCKED_COUNTRIES = T.let(new([IRAN, SYRIA]), TradeControls::Countries)
    # Used for enforcement: identifies high risk regions/cities that trigger compliance checks
    # Works with high_risk_geos_country_list to traverse country → region → city hierarchy
    HIGH_RISK_FLAGGABLE_REGIONS_LIST = T.let(new([CRIMEA, LUHANSK, DONETSK_OBLAST]), TradeControls::Countries)

    REGIONS_WITH_CITY_ENFORCEMENT = T.let(new([LUHANSK, DONETSK_OBLAST]), TradeControls::Countries)

    MARKETING_BLOCKED_COUNTRY_LIST = T.let(new([WESTERN_SAHARA, RUSSIA]), TradeControls::Countries)

    BILLING_ADDRESS_DENYLIST = T.let(new([CUBA, NORTH_KOREA]), TradeControls::Countries)
    SANCTIONED_COUNTRIES = T.let(new([NORTH_KOREA]), TradeControls::Countries)
    # Used for enforcement: triggers compliance checks that can lead to account restrictions
    # when users are detected from these countries (via high_risk_geo? method)
    HIGH_RISK_GEOS_COUNTRY_LIST = T.let(new([NORTH_KOREA, IRAN, BELARUS]), TradeControls::Countries)

    private_constant :BILLING_ADDRESS_DENYLIST, :GHES_BLOCKED_COUNTRIES, :HIGH_RISK_FLAGGABLE_REGIONS_LIST,
                     :HIGH_RISK_GEOS, :HIGH_RISK_GEOS_COUNTRY_LIST, :MARKETING_BLOCKED_COUNTRY_LIST,
                     :SANCTIONED_COUNTRIES

    sig { returns(TradeControls::Countries) }
    def self.billing_address_denylist
      BILLING_ADDRESS_DENYLIST
    end

    sig { returns(TradeControls::Countries) }
    def self.sanctioned
      SANCTIONED_COUNTRIES
    end

    # Used for enforcement: triggers compliance checks that can lead to account restrictions
    # when users are detected from these countries (via high_risk_geo? method)
    sig { returns(TradeControls::Countries) }
    def self.high_risk_geos_country_list
      HIGH_RISK_GEOS_COUNTRY_LIST
    end

    # This would be a scope+pluck if Country were an AR model
    sig { returns(T::Array[T.nilable(String)]) }
    def self.billing_address_blacklist_alpha3
      billing_address_denylist.alpha3
    end

    # This would be a scope if Country were an AR model
    sig { returns(T::Array[T::Array[String]]) }
    def self.currently_unsanctioned
      Braintree::Address::CountryNames.reject do |(_, _, alpha3, _)|
        billing_address_blacklist_alpha3.include?(alpha3.upcase)
      end
    end

    # wrapper around set of high risk geo locations
    sig { returns(TradeControls::Countries) }
    def self.high_risk_geos
      HIGH_RISK_GEOS
    end

    sig { returns(TradeControls::Countries) }
    def self.ghes_blocked_countries
      GHES_BLOCKED_COUNTRIES
    end

    sig { params(actor: Billing::Types::Account).returns(T::Array[TradeControls::Country]) }
    def self.copilot_auth_blocked_countries(actor:)
      countries = [BELARUS, CUBA, NORTH_KOREA, RUSSIA]
      countries << IRAN unless actor.feature_flag_enabled?(:sdn_copilot_vnext, default: false)
      countries.freeze
    end

    sig { returns(T::Array[T::Array[String]]) }
    def self.marketing_targeted_countries
      currently_unsanctioned.reject { |_, _, alpha3, _| MARKETING_BLOCKED_COUNTRY_LIST.alpha3.include?(alpha3&.upcase) }
    end

    sig { params(country_code: T.nilable(String)).returns(T::Boolean) }
    def self.currently_unsanctioned_country?(country_code)
      return false unless country_code.present?

      country = currently_unsanctioned.find do |_, alpha|
        alpha == country_code
      end

      country.present?
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
      return true if high_risk_geos_country_list.alpha2.include?(country)

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
