# typed: strict
# frozen_string_literal: true

module Notifyd
  # Helper module for working with agentic apps in notifyd adapters.
  # Provides cached access to agentic app bot IDs to avoid repeated lookups.
  module AgenticAppHelper
    # Default cache duration for agentic app bot IDs (1 hour)
    CACHE_DURATION = T.let(1.hour, ActiveSupport::Duration)
    CACHE_KEY = "notifyd:agentic_app_bot_ids"

    class << self
      # Returns a Set of bot IDs for all registered agentic apps.
      # Results are cached to avoid repeated database lookups.
      #
      # Returns Set<Integer> of bot IDs (excludes nil values)
      sig { returns(T::Set[Integer]) }
      def bot_ids
        GitHub.cache.fetch(CACHE_KEY, expires_in: CACHE_DURATION) do
          fetch_bot_ids
        end
      end

      # Checks if the given user ID belongs to an agentic app bot.
      #
      # user_id - Integer user ID to check
      #
      # Returns Boolean
      sig { params(user_id: T.nilable(Integer)).returns(T::Boolean) }
      def agentic_app?(user_id)
        return false if user_id.nil?

        bot_ids.include?(user_id)
      end

      private

      sig { returns(T::Set[Integer]) }
      def fetch_bot_ids
        ids = ::AgenticApp.all_agents.filter_map(&:bot_id)
        Set.new(ids)
      end
    end
  end
end
