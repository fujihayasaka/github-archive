# typed: true
#frozen_string_literal: true

module Platform
  module Loaders
    class UnlockedRepositoryCheck < Platform::Loader
      ACTIVE_UNLOCKS_CACHE_LIMIT = 1000

      class ActiveUnlocks
        class Cache < ActiveSupport::CurrentAttributes
          attribute :active_unlocks
        end
        private_constant :Cache

        def self.get
          Cache.active_unlocks ||= RepositoryUnlock.active.limit(ACTIVE_UNLOCKS_CACHE_LIMIT).load.tap do |unlocks|
            # Unlocking a repo is an infrequent and ephemeral operation.
            # If we hit this limit, something unusual is happening.
            # Possibly someone abusing the system trying to unlock repos in bulk.
            if unlocks.size >= ACTIVE_UNLOCKS_CACHE_LIMIT
              Failbot.report(RuntimeError.new("Active unlocks limit reached. Not all unlocks are being respected."))
            end
          end
        end

        def self.clear
          Cache.reset
        end
      end
      private_constant :ActiveUnlocks

      def self.clear_memoized_active_unlocks
        ActiveUnlocks.clear
      end

      def self.load(user, repository_id)
        self.for(user).load(repository_id)
      end

      def initialize(user)
        @user = user
      end

      def fetch(repository_ids)
        result = repository_ids.map { |repository_id| [repository_id, false] }.to_h

        return result unless user
        return result unless user.site_admin? || user.is_enterprise_managed? || GitHub.enterprise?

        scope = ActiveUnlocks.get.select do |unlock|
          unlock.unlocked_by_id == user.id && repository_ids.include?(unlock.repository_id)
        end
        return result if scope.empty?

        if user.site_admin?
          # GHES admin
          if GitHub.enterprise?
            scope.each do |unlock|
              result[unlock.repository_id] = true
            end
          else
            # Dotcom Staff user
            GitHub::PrefillAssociations.prefill_associations(ActiveUnlocks.get, :staff_access_grant)
            scope.each do |unlock|
              result[unlock.repository_id] = true if unlock.staff_access_grant&.active?
            end
          end

          return result
        end

        # EMU or GHES
        if user.is_enterprise_managed? || GitHub.enterprise?
          scope.each do |unlock|
            result[unlock.repository_id] = true
          end
        end

        result
      end

      private

      attr_reader :user
    end
  end
end
