# typed: strict
# frozen_string_literal: true

module TradeControls
  class OrgBillingEmailCompliance
    include OrgEmailCompliance

    sig { params(organization: ::Organization, event_source: T.nilable(String), kwargs: T.untyped).void }
    def initialize(organization:, event_source: nil, **kwargs)
      @organization = organization
      @reason = T.let(:organization_billing_email, Symbol)
      @email = T.let(organization.billing_email.to_s, String)
      @event_source = event_source
    end

    sig { override.returns(Organization) }
    def organization
      @organization
    end

    sig { override.returns(String) }
    def email
      @email
    end

    sig { override.returns(T.any(String, Symbol)) }
    def reason
      @reason
    end

    sig { override.returns(T.nilable(String)) }
    def event_source
      @event_source
    end
  end
end
