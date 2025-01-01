# typed: strict
# frozen_string_literal: true

module Actions::Cache
  # Checks if results-based cache should be used for the given actor.
  # If the actor is a repository, it will also check if the owner is opted out.
  sig do
    params(
      actor: T.nilable(GitHub::FlipperActor),
    ).returns(T::Boolean)
  end
  def self.use_v2?(actor)
    return false if actor.nil?
    return false if GitHub.enterprise?
    return false if actor.feature_enabled?(:actions_opt_out_of_cache_service_v2)

    if actor.is_a?(Repository)
      return false if actor.owner&.feature_enabled?(:actions_opt_out_of_cache_service_v2)
    end

    actor.feature_enabled?(:actions_uses_cache_service_v2)
  end
end
