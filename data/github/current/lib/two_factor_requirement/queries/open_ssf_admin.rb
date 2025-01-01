# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class OpenSSFAdmin < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      # Builds a raw query for trino that finds users who are Open Source Security Foundation (Open SSF) repo admins limited by time.
      # Always use `filtered_users` instead of `delta.snapshots.github_mysql1_users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          (
            SELECT  distinct(a.actor_id) as id
            FROM    delta.snapshots.github_mysql_iam_abilities_abilities a
            INNER JOIN filtered_users u on u.id = a.actor_id
            LEFT JOIN delta.snapshots.github_mysql_iam_abilities_abilities p ON p.actor_type = a.subject_type AND p.actor_id = a.subject_id
            WHERE   a.actor_type = 'User'
              AND a.subject_type IN ('Team', 'Organization', 'Repository')
              AND (
                (
                  a.subject_type = 'Repository'
                  AND a.action = 2
                )
                OR
                (
                  p.subject_type = 'Repository'
                  AND p.actor_type IN ('Team', 'Organization')
                  AND p.action = 2
                )
              )
            AND a.subject_id IN (
              #{OPEN_SSF_REPO_IDS.join(',')}
            )
            #{"AND (a.created_at > timestamp '#{lookback_timestamp}' OR a.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          )
          UNION
          (
            SELECT  distinct(owner_id) AS id
            FROM    delta.snapshots.github_mysql1_repositories r
            INNER JOIN filtered_users u ON u.id = r.owner_id
            WHERE r.id IN (
              #{OPEN_SSF_REPO_IDS.join(',')}
            )
            #{"AND (r.created_at > timestamp '#{lookback_timestamp}' OR r.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
          )
        )
      end
    end
  end
end
