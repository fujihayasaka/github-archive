# typed: strict
# frozen_string_literal: true

module TradeControls
  # Provides shared behavior for flagging blocklisted domains
  module DomainFlagging
    include Compliance

    extend T::Helpers

    abstract!

    sig { returns(T::Boolean) }
    def violation?
      if organization.present?
        full_restriction_violation? || tier_1_restriction_violation?
      else
        sanctioned_country.present? || sanctioned_domain.present?
      end
    end

    private

    sig { abstract.returns(String) }
    def domain_field; end

    sig { abstract.returns(Symbol) }
    def domain_field_type; end

    sig { returns(T.nilable(String)) }
    def url_tld
      uri = URI.parse(domain_field)
      uri = uri.scheme.nil? ? "http://#{domain_field}" : domain_field
      Addressable::URI.parse(uri).tld
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError, PublicSuffix::DomainInvalid
      nil
    end

    sig { returns(String) }
    def email_tld
      return "" if domain_field.blank?

      domain_field.split(".").last.to_s.strip
    end

    sig { returns(T.nilable(String)) }
    def tld
      @tld ||= T.let(
      case domain_field_type
      when :email
        email_tld
      when :website_url
        url_tld
      else
        nil
      end, T.nilable(String))
    end

    sig { returns(T.nilable(String)) }
    def url_domain
      uri = URI.parse(domain_field)
      uri = uri.scheme.nil? ? "http://#{domain_field}" : domain_field
      Addressable::URI.parse(uri).domain
    rescue Addressable::URI::InvalidURIError, URI::InvalidURIError, PublicSuffix::DomainInvalid
      nil
    end

    sig { returns(String) }
    def email_domain
      return "" if domain_field.blank?

      domain_field.split("@").last.to_s.strip
    end

    sig { returns(T.nilable(String)) }
    def domain
      @domain ||= T.let(
      case domain_field_type
      when :email
        email_domain
      when :website_url
        url_domain
      else
        nil
      end, T.nilable(String))
    end

    sig { returns(T.nilable(TradeControls::Country)) }
    def inferred_country
      return if tld.blank?

      upcase_tld = T.must(tld).upcase
      @inferred_country ||= T.let(Country.from_braintree(Braintree::Address::CountryNames.find { |c| c[1] == upcase_tld }), T.nilable(TradeControls::Country))
    end

    sig { returns(T.nilable(TradeControls::Country)) }
    def sanctioned_country
      @sanctioned_country ||= T.let(Countries.sanctioned.find { |c| c == T.must(inferred_country) }, T.nilable(TradeControls::Country)) if inferred_country.present?
    end

    sig { returns(T.nilable(String)) }
    def sanctioned_domain
      return if domain.blank?

      downcased_domain = T.must(domain).downcase
      @sanctioned_domain ||= T.let(downcased_domain, T.nilable(String)) if Domains::SANCTIONED_DOMAINS.include?(downcased_domain)

      @sanctioned_domain ||= Domains::SANCTIONED_TLDS.find { |d| downcased_domain.end_with?(d) }
    end
  end
end
