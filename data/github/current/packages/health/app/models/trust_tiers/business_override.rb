# typed: strict
# frozen_string_literal: true

module TrustTiers
  # Manages manual trust tier overrides for enterprise accounts.
  module BusinessOverride
    class << self
      sig { params(business: Business).returns(Integer) }
      def get(business)
        EnterpriseAccounts::KV.store.get(key_for(business)).value { nil }.to_i
      end

      sig { params(business: Business, trust_tier: Integer).void }
      def set(business, trust_tier)
        if trust_tier > 0
          EnterpriseAccounts::KV.store.set(key_for(business), trust_tier.to_s, expires: nil)
        else
          EnterpriseAccounts::KV.store.del(key_for(business))
        end
      end

      private

      sig { params(business: Business).returns(String) }
      def key_for(business)
        "business:#{business.id}:trust_tier_override"
      end
    end
  end
end
