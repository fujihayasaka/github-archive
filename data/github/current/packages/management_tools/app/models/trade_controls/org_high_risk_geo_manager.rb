# typed: strict
# frozen_string_literal: true

module TradeControls
  class OrgHighRiskGeoManager
    include DomainFlagging
    extend T::Sig

    sig { params(email: T.nilable(String), website_url: T.nilable(String)).void }
    def initialize(email: nil, website_url: nil)
      @email = T.let(email.to_s, String)
      @website_url = T.let(website_url.to_s, String)
    end

    sig { returns(T.nilable(String)) }
    def high_risk_geo
      if high_risk_inferred_country?
        T.must(inferred_country).alpha3.presence || T.must(inferred_country).alpha2
      end
    end

    private

    sig { returns(T::Boolean) }
    def high_risk_inferred_country?
      return false if inferred_country.blank?

      TradeControls::Countries.high_risk_geos.include?(T.must(inferred_country))
    end

    sig { override.returns(String) }
    def domain_field
      @email.presence || @website_url
    end

    sig { override.returns(Symbol) }
    def domain_field_type
      @email.present? ? :email : :website_url
    end
  end
end
