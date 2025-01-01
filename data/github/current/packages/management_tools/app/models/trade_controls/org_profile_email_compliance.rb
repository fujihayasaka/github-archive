# typed: strict
# frozen_string_literal: true

module TradeControls
  class OrgProfileEmailCompliance
    include OrgEmailCompliance
    extend T::Sig

    sig { params(organization: ::Organization, kwargs: T.untyped).void }
    def initialize(organization:, **kwargs)
      @organization = organization
      @reason = T.let(:organization_profile_email, Symbol)
      @email = T.let(T.unsafe(organization).profile_email.to_s, String)
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
  end
end
