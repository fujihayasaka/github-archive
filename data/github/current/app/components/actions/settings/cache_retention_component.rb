# typed: true
# frozen_string_literal: true

module Actions
  module Settings
    # This exists in addition to the GHES one as that one came first and there is some divergence in functionality
    # For retention policies, entities without explicit limits are treated as having the default (7 days).
    # The minimum retention across all entities (explicit or defaulted) is applied. This allows lower-level
    # entities to set limits LOWER than the default without requiring opt-in from higher entities, but
    # raising limits above default requires all entities to have explicit policies set.
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
        unless @retention_limits&.any?
          return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT
        end

        # If all entities have limits set, use the lowest
        if @retention_limits.all? { |e| e[:retain_for].present? }
          return @retention_limits.min_by { |e| e[:retain_for] }[:retain_for]
        end

        # Find the lowest explicitly set (non-nil) retention limit
        set_limits = @retention_limits.select { |e| e[:retain_for].present? }

        return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT unless set_limits.any?

        lowest_set_limit = set_limits.min_by { |e| e[:retain_for] }[:retain_for]

        # Opt-in: only use a stricter limit (below default), otherwise use default
        [lowest_set_limit, ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT].min
      end

      memoize def upper_limit
        return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT unless @retention_limits&.any?

        # Repo/Org/Enterprise with no enclosing entities can set up to entity-specific max.
        if @retention_limits.length == 1
          if @entity.is_a?(Repository) && @entity.public?
            return ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PUBLIC
          else
            return ActionsPolicyHelper::GLOBAL_MAX_CACHE_RETENTION_DAYS_PRIVATE
          end
        end

        enclosing_entities = @retention_limits.select { |el| el[:entity] != @entity }
        is_any_enclosing_entity_unset = enclosing_entities.any? { |e| e[:retain_for].nil? }

        return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT if is_any_enclosing_entity_unset

        # All enclosing entities have set limits, so the upper limit is the lowest of those.
        enclosing_entities.min_by { |e| e[:retain_for] }[:retain_for]
      end

      # Returns the entity (Org/Enterprise) that imposes the lowest retention limit, or nil if no limits are set.
      # This is used to show the user who is imposing the limit on retention, hence excluding the current entity.
      # If there are no limits set, it returns nil, implying the repository is bound by global limit.
      def entity_imposing_limit
        return nil unless @retention_limits&.any? && @retention_limits.length > 1

        enclosing_entities = @retention_limits.select { |el| el[:entity] != @entity }
        is_any_enclosing_entity_unset = enclosing_entities.any? { |e| e[:retain_for].nil? }

        return enclosing_entities.min_by { |e| e[:retain_for] } unless is_any_enclosing_entity_unset

        # One or multiple enclosing entities are unset. If both, return higher (enterprise).
        enclosing_entities.find { |e| e[:retain_for].nil? && e[:entity].is_a?(Business) } ||
        enclosing_entities.find { |e| e[:retain_for].nil? && e[:entity].is_a?(Organization) }
      end
    end
  end
end
