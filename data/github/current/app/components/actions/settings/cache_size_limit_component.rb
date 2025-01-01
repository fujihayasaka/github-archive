# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    # This exists in addition to the GHES one as that one came first and there is some divergence in functionality
    class CacheSizeLimitComponent < ApplicationComponent
      def initialize(entity:, relevant_entities:)
        @entity = entity
        @cache_limits = ActionsPolicyHelper.get_cache_limits_from_entities(relevant_entities)
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
        # If no cache limits are set at all, show the max applicable limit
        unless @cache_limits&.any?
          return @entity.is_a?(Repository) ? 10 : ActionsPolicyHelper::GLOBAL_MAX_CACHE_SIZE_GB
        end

        current_entity_limit = @cache_limits.find { |entity_limit| entity_limit[:entity] == @entity }
        current_limit = current_entity_limit&.[](:storage_limit)

        # If no limit is set for the current entity, show the max applicable limit, or 10 if repo.
        if current_limit.nil?
          if @entity.is_a?(Repository)
            return ActionsPolicyHelper::REPO_CACHE_SIZE_DEFAULT_GB
          elsif @entity.is_a?(Organization)
            enterprise_limit = @cache_limits.find { |e| e[:entity].is_a?(Business) }
            return enterprise_limit&.[](:storage_limit) || ActionsPolicyHelper::GLOBAL_MAX_CACHE_SIZE_GB
          else
            return ActionsPolicyHelper::GLOBAL_MAX_CACHE_SIZE_GB
          end
        end

        # If there's an enclosing entity imposing a lower limit, use that instead
        if entity_imposing_limit && entity_imposing_limit[:storage_limit] < current_limit
          entity_imposing_limit[:storage_limit]
        else
          current_limit
        end
      end

      memoize def upper_limit
        return ActionsPolicyHelper::GLOBAL_MAX_CACHE_SIZE_GB unless @cache_limits&.any?

        # Get enclosing entities (exclude current entity)
        enclosing_limits = @cache_limits.select do |entity_limit|
          entity_limit[:storage_limit] && entity_limit[:entity] != @entity
        end.map { |entity_limit| entity_limit[:storage_limit] }

        enclosing_limits.empty? ? ActionsPolicyHelper::GLOBAL_MAX_CACHE_SIZE_GB : enclosing_limits.min
      end

      # Returns the entity (Org/Enterprise) that imposes the lowest cache size limit, or nil if no limits are set.
      # This is used to show the user who is imposing the limit on cache size, hence excluding the current entity.
      # If there are no limits set, it returns nil, implying the repository is bound by global limit.
      def entity_imposing_limit
        return nil unless @cache_limits&.any?

        # Exclude the current entity - we only want enclosing entities
        limits_with_values = @cache_limits.select do |entity_limit|
          entity_limit[:storage_limit] && entity_limit[:entity] != @entity
        end

        return nil unless limits_with_values.any?

        limits_with_values.min_by { |entity_limit| entity_limit[:storage_limit] }
      end
    end
  end
end
