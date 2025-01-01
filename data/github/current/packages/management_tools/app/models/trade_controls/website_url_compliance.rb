# typed: strict
# frozen_string_literal: true

module TradeControls
  class WebsiteUrlCompliance
    include Compliance
    include DomainFlagging
    extend T::Sig

    sig { params(organization: T.nilable(T.any(::User, ::Organization)), website_url: T.nilable(String), kwargs: T.untyped).void }
    def initialize(organization:, website_url:, **kwargs)
      @organization = organization
      @website_url = T.let(website_url.to_s, String)
      @reason = T.let(:website_url, Symbol)
    end

    sig { override.returns(T.nilable(T.any(::User, ::Organization))) }
    def organization
      @organization
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end

    sig { override.returns(T::Boolean) }
    def full_restriction_violation?
      if organization
        T.must(organization).charged_account? && sanctioned_country.present?
      else
        sanctioned_country.present?
      end
    end

    sig { override.returns(T::Boolean) }
    def tier_1_restriction_violation?
      return false unless organization
      T.must(organization).uncharged_account? && sanctioned_country.present?
    end

    sig { override.returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        reason: reason,
        country: sanctioned_country&.name,
        website_url: @website_url,
      }
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { override.params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(website_url: @website_url, reason: reason, country: sanctioned_country)
    end

    sig { returns(T::Boolean) }
    def sdn_suspend?
      tld&.upcase == "KP"
    end

    private

    sig { override.returns(String) }
    def domain_field
      @website_url
    end

    sig { override.returns(Symbol) }
    def domain_field_type
      :website_url
    end
  end
end
