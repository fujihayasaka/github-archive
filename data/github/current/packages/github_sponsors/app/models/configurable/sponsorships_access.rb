# typed: true
# frozen_string_literal: true

# Configurable used to control member orgs access for creating sponsorships
module Configurable
  module SponsorshipsAccess
    extend T::Sig
    extend T::Helpers

    requires_ancestor { Configurable }

    KEY = "sponsorships_access".freeze

    sig { params(actor: User).returns(T::Boolean) }
    def grant_sponsorships_access(actor:)
      config.enable(KEY, actor)
    end

    sig { params(actor: User).returns(T::Boolean) }
    def revoke_sponsorships_access(actor:)
      config.disable(KEY, actor)
    end

    sig { returns(T::Boolean) }
    def has_sponsorships_access?
      # sponsorships enabled by default if this org is not member of a business
      return true unless configuration_owner&.is_a?(Business)

      # validate key was explicitly set to true on this org
      !!config.local?(KEY) && config.enabled?(KEY)
    end
  end
end
