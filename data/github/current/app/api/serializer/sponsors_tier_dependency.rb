# typed: strict
# frozen_string_literal: true

module Api::Serializer::SponsorsTierDependency
  extend T::Sig
  extend T::Helpers

  requires_ancestor { Api::Serializer }

  # Creates a Hash to be serialized to JSON.
  #
  # sponsors_tier - SponsorsTier instance
  #
  # Returns a Hash if the SponsorsTier exists, or nil.
  sig do
    params(
      sponsors_tier: T.nilable(SponsorsTier),
      options: T::Hash[T.untyped, T.untyped]
    ).returns(T.nilable(T::Hash[Symbol, T.untyped]))
  end
  def sponsors_tier_hash(sponsors_tier, options)
    return nil unless sponsors_tier

    {
      node_id: global_id_for(sponsors_tier, options),
      created_at: time(sponsors_tier.created_at),
      description: sponsors_tier.description,
      monthly_price_in_cents: sponsors_tier.monthly_price_in_cents,
      monthly_price_in_dollars: sponsors_tier.monthly_price_in_dollars.to_i,
      name: sponsors_tier.name,
      is_one_time: sponsors_tier.one_time?,
      is_custom_amount: sponsors_tier.custom?,
    }
  end
end
