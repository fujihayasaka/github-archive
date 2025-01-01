# typed: true
# frozen_string_literal: true

module Actions
  module Settings

    # This exists in addition to the GHES one as that one came first and there is some divergence in functionality
    class CacheRetentionComponent < ApplicationComponent
      def initialize(entity:, relevant_entities:)
        @entity = entity
        @retention_limits = ActionsPolicyHelper.get_cache_retention_from_entities(relevant_entities)
      end

      def update_cache_retention_size_path
        if @entity.is_a?(Business)
          settings_actions_cache_retention_enterprise_path(@entity.slug)
        elsif @entity.is_a?(Organization)
          settings_org_actions_cache_retention_path(@entity)
        else
          repo_actions_cache_retention_path(repository: @entity, user_id: @entity.owner)
        end
      end

      memoize def value
        # If no cache limits are set at all, show the max applicable limit
        unless @retention_limits&.any?
          return @entity.is_a?(Repository) ? ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT : ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
        end

        current_entity_limit = @retention_limits.find { |entity_limit| entity_limit[:entity] == @entity }
        current_limit = current_entity_limit&.dig(:retain_for)

        # If no limit is set for the current entity, show the max applicable limit, or 7 if repo.
        if current_limit.nil?
          if @entity.is_a?(Repository)
            return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT
          elsif @entity.is_a?(Organization)
            enterprise_limit = @retention_limits.find { |e| e[:entity].is_a?(Business) }
            return enterprise_limit&.[](:retain_for) || ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
          else
            return ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
          end
        end

        @retention_limits.map { |e| e[:retain_for] }.compact.min
      end

      memoize def upper_limit
        if !@retention_limits&.any?
          return (@entity.is_a?(Repository) && @entity.public?) ? ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PUBLIC : ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
        end

        limiting_entity = entity_imposing_limit
        return limiting_entity[:retain_for] if limiting_entity

        (@entity.is_a?(Repository) && @entity.public?) ? ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PUBLIC : ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
      end

      # Returns the entity (Org/Enterprise) that imposes the lowest retention limit, or nil if no limits are set.
      # This is used to show the user who is imposing the limit on retention, hence excluding the current entity.
      # If there are no limits set, it returns nil, implying the repository is bound by global limit.
      def entity_imposing_limit
        return nil unless @retention_limits&.any?

        # Exclude the current entity - we only want enclosing entities
        limits_with_values = @retention_limits.select do |entity_limit|
          entity_limit[:retain_for] && entity_limit[:entity] != @entity
        end

        return nil unless limits_with_values.any?

        limits_with_values.min_by { |entity_limit| entity_limit[:retain_for] }
      end
    end
  end
end
