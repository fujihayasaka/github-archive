# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    # This exists in addition to the GHES one as that one came first and there is some divergence in functionality
    class CacheSizeLimitComponent < ApplicationComponent
      def initialize(entity:, relevant_entities:)
        @entity = entity
        @cache_limits = ActionsPolicyHelper.get_cache_limits_from_entities(relevant_entities) # maps all entities to limits (or nulls if unset)
      end

      def update_maximum_cache_size_path
        if @entity.is_a?(Business)
          settings_actions_cache_size_limit_enterprise_path(@entity.slug)
        elsif @entity.is_a?(Organization)
          settings_org_actions_cache_size_path(@entity)
        else
          repo_actions_cache_size_path(repository: @entity, user_id: @entity.owner)
        end
      end

      def cache_size_limit_header
        "Cache size eviction limit"
      end

      def cache_size_limit_description
        "Use this limit to control when cache evictions occur. Exceeding this limit will trigger evictions of the least recently used cache. Note this limit should not be used for controlling costs."
      end

      memoize def value
        unless @cache_limits&.any?
          return ActionsPolicyHelper::REPO_CACHE_SIZE_DEFAULT_GB # No limits set, return default for *all types*
        end

        # For this functionality to be truly opt-in, enterprises must set limits before enclosed organisations can set their limits
        # Only then can repositories at the bottom of this hierarchy set a limit.
        is_any_entity_unset = @cache_limits.any? { |e| e[:storage_limit].nil? }

        return ActionsPolicyHelper::REPO_CACHE_SIZE_DEFAULT_GB if is_any_entity_unset

        # Policy is set at all levels so we can just take the lowest.
        @cache_limits.min_by { |e| e[:storage_limit] }[:storage_limit]
      end

      memoize def upper_limit
        return ActionsPolicyHelper::REPO_CACHE_SIZE_DEFAULT_GB unless @cache_limits&.any?

        # Repo/Org/Enterprise with no enclosing entities can set up to global max.
        if @cache_limits.length == 1
          return ActionsPolicyHelper::GLOBAL_MAX_CACHE_SIZE_GB
        end

        enclosing_entities = @cache_limits.select { |el| el[:entity] != @entity }
        is_any_enclosing_entity_unset = enclosing_entities.any? { |e| e[:storage_limit].nil? }

        return ActionsPolicyHelper::REPO_CACHE_SIZE_DEFAULT_GB if is_any_enclosing_entity_unset

        # All enclosing entities have set limits, so the upper limit is the lowest of those.
        enclosing_entities.min_by { |e| e[:storage_limit] }[:storage_limit]
      end

      # Returns the entity (Org/Enterprise) that imposes the lowest cache size limit, or nil if no limits are set.
      # This is used to show the user who is imposing the limit on cache size, hence excluding the current entity.
      # If there are no limits set, it returns nil, implying the repository is bound by global limit.
      def entity_imposing_limit
        return nil unless @cache_limits&.any? && @cache_limits.length > 1

        enclosing_entities = @cache_limits.select { |el| el[:entity] != @entity }
        is_any_enclosing_entity_unset = enclosing_entities.any? { |e| e[:storage_limit].nil? }

        return enclosing_entities.min_by { |e| e[:storage_limit] } unless is_any_enclosing_entity_unset

        # One or multiple enclosing entities are unset. If both, return higher (enterprise).
        enclosing_entities.find { |e| e[:storage_limit].nil? && e[:entity].is_a?(Business) } ||
        enclosing_entities.find { |e| e[:storage_limit].nil? && e[:entity].is_a?(Organization) }
      end
    end
  end
end
