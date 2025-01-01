# typed: true
# frozen_string_literal: true

require_relative "base_query"

module Authorization
  module Queries
    class MostCapableActionBetween < BaseQuery
      include Scientist

      attr_reader :actor, :subject

      def initialize(actor:, subject:)
        @actor = actor
        @subject = subject
      end

      # Returns string representation of the Ability action (read, write, admin)
      def execute_implementation
        return default_result unless subject.participates? && actor.participates?

        # if possible leverage the cache key set by Platform::Loaders::Ability to return early
        if PermissionCache.key?(ability_loader_cache_key)
          level = PermissionCache.get(ability_loader_cache_key)
          return Ability.actions.invert[level].dup
        end
        GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:ability_loader"])
        ability = Authorization::Queries::MostCapableAbilityBetween.new(actor: actor, subject: subject).execute

        # conditionally populate the ability loader cache with the action value
        # this matches the behavior of Platform::Loaders::Ability which does cache nil
        PermissionCache.set(ability_loader_cache_key, Ability.actions[ability&.action])

        # dup to get a separate object since the Authorization::Result#decorate wants to extend the object
        ability&.action.dup
      end

      def validation_errors
        errors = []

        unless valid_actor?(actor)
          errors << validation_error(:invalid_actor, actor: actor)
        end

        unless valid_subject?(subject)
          errors << validation_error(:invalid_subject, subject: subject)
        end

        errors
      end

      private

      ABILITY_LOADER_CACHE_PREFIX = "ability_loader" # this is the platform ability loader namespace

      def ability_loader_cache_key
        [ABILITY_LOADER_CACHE_PREFIX, @actor.ability_type, @actor.ability_id, @subject.ability_type, @subject.ability_id]
      end
    end
  end
end
