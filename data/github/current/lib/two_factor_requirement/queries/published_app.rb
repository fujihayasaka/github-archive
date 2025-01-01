# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class PublishedApp < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      # Builds a raw query for trino that finds users who have published an app limited by time.
      # Always use `filtered_users` instead of `delta.snapshots.github_mysql1_users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          (
            SELECT distinct(u.id)
            FROM filtered_users u
            INNER JOIN delta.snapshots.github_mysql1_repositories r ON r.owner_id = u.id
            INNER JOIN delta.snapshots.github_mysql1_repository_actions ra ON r.id = ra.repository_id
            #{"AND (ra.created_at > timestamp '#{lookback_timestamp}' OR ra.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          )
          UNION
          (
            SELECT DISTINCT(u.id)
            FROM filtered_users u
            INNER JOIN hive.canonical.apps_current a on a.owner_dotcom_id = u.id
            WHERE a.in_marketplace = true
            AND a.is_github_owned = false
            #{"AND (a.created_at > timestamp '#{lookback_timestamp}' OR a.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          )
        )
      end
    end
  end
end
