# typed: strict
# frozen_string_literal: true

# Opt-in registry of "this flag is primarily meaningful per-actor" preferences,
# consumed by `bin/toggle-feature-flag` to prevent devs from enabling such a
# flag globally without an actor scope. Teams that roll out flags in stages
# (e.g. user -> org -> repo -> global) can register here so they catch
# rollout-only regressions early instead of after a production deploy.
module FeatureFlag
  class RolloutPreference
    SUPPORTED_SCOPES = T.let([:organization, :repository, :user, :business].freeze, T::Array[Symbol])

    # Flag name -> ordered list of recommended actor scopes (most-preferred first).
    REGISTRY = T.let({
      # Repo Issues Sidebar - pinned views feature, rolling out org-by-org before
      # going global.
      issue_pinned_views: [:organization, :repository, :user],
      issue_pinned_views_index_page: [:organization, :repository, :user],
      issue_pinned_views_projects_react: [:organization, :repository, :user],
    }.freeze, T::Hash[Symbol, T::Array[Symbol]])

    sig { params(flag_name: Symbol).returns(T.nilable(T::Array[Symbol])) }
    def self.recommended_scopes(flag_name)
      REGISTRY[flag_name]
    end

    sig { params(flag_name: Symbol).returns(T::Boolean) }
    def self.actor_required?(flag_name)
      REGISTRY.key?(flag_name)
    end
  end
end
