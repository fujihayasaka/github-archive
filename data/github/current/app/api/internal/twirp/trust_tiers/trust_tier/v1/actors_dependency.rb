# typed: true
# frozen_string_literal: true

module Api::Internal::Twirp::TrustTiers
  module TrustTier
    module V1
      module ActorsDependency
        def get_tier_for_actor(actor, client_name)
          if actor.is_a?(User) && actor.user?
            TrustTiers::Tier.for_billable_owner(actor, client_name)
          elsif actor.is_a?(Bot)
            TrustTiers::Tier.for_billable_owner(actor, client_name)
          elsif actor.is_a?(Organization) && actor.organization?
            TrustTiers::Tier.for_billable_owner(actor, client_name)
          elsif actor.is_a?(Repository)
            TrustTiers::Tier.for_repository(actor, client_name)
          elsif actor.is_a?(Business)
            TrustTiers::Tier.for_billable_owner(actor, client_name)
          else
            { id: actor.id, type: :TYPE_INVALID }
          end
        end
      end
    end
  end
end
