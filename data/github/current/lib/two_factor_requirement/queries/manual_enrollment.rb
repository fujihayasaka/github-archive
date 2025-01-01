# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class ManualEnrollment < Base
      # Builds a raw query for presto that finds users to enroll in 2FA requirement if they are added to GitHub.flipper[:bulwark_two_factor_required_manual_enrollment].
      # Always use `filtered_users` instead of `#{self.users_table}`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        feature = FlipperFeature.find_by(name: :bulwark_two_factor_required_manual_enrollment)
        actor_gates = feature&.flipper_gates&.actor_gates(actor_type: "User") || []

        raise ArgumentError, "No users found for feature flag bulwark_two_factor_required_manual_enrollment" if actor_gates.empty?

        %Q(
          SELECT DISTINCT (id)
          FROM filtered_users u
          WHERE u.login IN (#{actor_gates.map { |gate| "'#{gate.actor.display_login}'" }.join(', ')})
        )
      end
    end
  end
end
