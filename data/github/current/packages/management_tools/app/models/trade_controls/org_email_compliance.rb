# typed: strict
# frozen_string_literal: true

module TradeControls
  module OrgEmailCompliance
    include Compliance
    include DomainFlagging
    extend T::Helpers

    abstract!

    sig { abstract.returns(String) }
    def email; end

    sig { abstract.returns(Organization) }
    def organization; end

    sig { returns(T::Boolean) }
    def full_restriction_violation?
      organization.charged_account? && sanctioned_country.present?
    end

    sig { returns(T::Boolean) }
    def tier_1_restriction_violation?
      organization.uncharged_account? && sanctioned_country.present?
    end

    sig { returns(T::Hash[T.any(Symbol, String), T.untyped]) }
    def to_hydro
      {
        reason: reason,
        country: sanctioned_country&.name,
        email: email,
      }
    end

    sig { returns(T::Boolean) }
    def sdn_suspend?
      tld&.upcase == "KP"
    end

    # Internal: invoked by Instrumentation::Model when expanding event_payload
    sig { params(kwargs: T.untyped).returns(T.untyped) }
    def event_context(**kwargs)
      Context::Expander.expand(email: email, reason: reason, country: sanctioned_country)
    end

    private

    sig { override.returns(String) }
    def domain_field
      email
    end

    sig { override.returns(Symbol) }
    def domain_field_type
      :email
    end
  end
end
