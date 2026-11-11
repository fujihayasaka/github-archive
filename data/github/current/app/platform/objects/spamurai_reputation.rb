# typed: true
# frozen_string_literal: true

module Platform
  module Objects
    class SpamuraiReputation < Platform::Objects::Base
      description "A common reputation type for Spamurai."

      # Determine whether the viewer can access this object via the API (called internally).
      # This is where Egress checks for OAuth scopes and GitHub Apps go.
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_api_can_access?(permission, _object)
        permission.hidden_from_public?(self)
      end

      # Determine whether the viewer can see this object (called internally).
      # Returns `true`, `false`, or `Promise` resolving to `true` or `false`
      def self.async_viewer_can_see?(permission, object)
        Platform::Objects::Base::SiteAdminCheck.viewer_is_site_admin?(permission.viewer, self.class.name)
      end

      visibility :internal

      minimum_accepted_scopes ["site_admin"]

      field :sample_size, Integer, "Sample size.", null: false
      field :not_spammy_sample_size, Integer, "Not spammy sample size.", null: false
      field :spammy_sample_size, Integer, "Spammy sample size.", null: false
      field :reputation, Float, "Reputation.", null: false
      field :reputation_lower_bound, Float, "Reputation lower bound.", null: false
      field :plus_minus, Float, "Plus minus.", null: false
      field :minimum_reputation, Float, "Minimum reputation.", null: false
      field :maximum_reputation, Float, "Maximum reputation.", null: false
      field :warning_level, String, "Reputation warning level.", null: false
    end
  end
end
