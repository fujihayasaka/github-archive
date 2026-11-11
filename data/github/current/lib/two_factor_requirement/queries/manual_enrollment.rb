# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class ManualEnrollment < Base
      # Builds a raw query for trino that finds users to enroll in 2FA requirement if they are added to the `bulwark_two_factor_required_manual_enrollment` feature flag.
      # Always use `filtered_users` instead of `delta.snapshots.github_mysql1_users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        actor_ids_by_class = GitHub::VexiActor.actor_ids_by_class_or_raise(:bulwark_two_factor_required_manual_enrollment)
        user_actor_ids = actor_ids_by_class.to_h[User] || []

        raise ArgumentError, "No users found for feature flag bulwark_two_factor_required_manual_enrollment" if user_actor_ids.empty?

        user_logins = User.where(id: user_actor_ids).pluck(:display_login)

        %Q(
          SELECT DISTINCT (id)
          FROM filtered_users u
          WHERE u.login IN (#{user_logins.map { |login| "'#{login}'" }.join(', ')})
        )
      end
    end
  end
end
