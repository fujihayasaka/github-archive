# typed: false
# frozen_string_literal: true

module Api::Serializer::InteractionLimitsDependency
  def interaction_ability_hash(repo, options = {})
    ability = RepositoryInteractionAbility.new(repo)

    limit, origin, expires_at = Promise.all([
      ability.async_overall_active_limit,
      ability.async_active_limit_origin,
      ability.async_overall_active_limit_expiry,
    ]).sync

    return {} if limit == :no_limit

    # `sockpuppet_disallowed` is our internal name, but users know it as
    # `existing_users`, so we have to special case this.
    limit_name = limit == :sockpuppet_disallowed ? "existing_users" : limit

    {
      limit: limit_name,
      origin: origin,
      expires_at: time(expires_at),
    }
  end
end
