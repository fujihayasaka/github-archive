# typed: true
# frozen_string_literal: true

require_relative "async_base_query"

module Authorization
  module Queries
    class AsyncMostCapableActionBetween < AsyncBaseQuery
      include Scientist

      attr_reader :actor, :subject

      def initialize(actor:, subject:)
        @actor = actor
        @subject = subject
      end

      # Returns Promise<string> representation of the Ability action (read, write, admin)
      def execute_implementation
        return Promise.resolve(default_result) unless subject.participates? && actor.participates?

        # Use the MostCapableAbilityBetween cache to get the action if possible
        if PermissionCache.key?(most_capable_ability_cache_key)
          cached_ability = PermissionCache.get(most_capable_ability_cache_key)
          return Promise.resolve(cached_ability&.action&.dup)
        end
        GitHub.dogstats.increment("ability.cache", tags: ["result:miss", "namespace:#{MOST_CAPABLE_ABILITY_CACHE_PREFIX}"])

        Platform::Loaders::Ability.load(actor, subject).then do |action|
          # we cannot set MCAB cache here because we only have the action, not the full ability object
          action.nil? ? nil : AsyncMostCapableActionBetween.reverse_action_map[action].dup
        end
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

      def self.reverse_action_map
        @@reverse_action_map ||= Ability.actions.invert
      end

      private

      MOST_CAPABLE_ABILITY_CACHE_PREFIX = "most_capable_ability_between" # see lib/authorization/queries/most_capable_ability_between.rb
      def most_capable_ability_cache_key
        [MOST_CAPABLE_ABILITY_CACHE_PREFIX, actor.ability_type, actor.ability_id, subject.ability_type, subject.ability_id]
      end
    end
  end
end
