# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class CreatedRelease < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      # Builds a raw query for trino that finds users who have created a release limited by time.
      # Always use `filtered_users` instead of `delta.snapshots.github_mysql1_users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          SELECT DISTINCT(u.id)
          FROM filtered_users u
          INNER JOIN delta.snapshots.github_mysql1_releases rl ON rl.author_id = u.id
          #{"WHERE (rl.created_at > timestamp '#{lookback_timestamp}' OR rl.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
        )
      end
    end
  end
end
