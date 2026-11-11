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
        unless @retention_limits&.any?
          return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT
        end

        # For this functionality to be truly opt-in, enterprises must set limits before enclosed organisations can set their limits
        # Only then can repositories at the bottom of this hierarchy set a limit.
        is_any_entity_unset = @retention_limits.any? { |e| e[:retain_for].nil? }

        return ActionsPolicyHelper::CACHE_RETENTION_DAYS_DEFAULT if is_any_entity_unset

        # Policy is set at all levels so we can just take the lowest.
        @retention_limits.min_by { |e| e[:retain_for] }[:retain_for]
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
