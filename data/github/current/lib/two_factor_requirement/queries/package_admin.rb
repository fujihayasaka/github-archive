# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class PackageAdmin < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      def cohort_ctes(lookback_timestamp: nil)
        %Q(
          , publishing_repos AS (
            SELECT DISTINCT d.repository_id as id
            FROM delta.snapshots.dependency_graph_dg_packages d
            INNER JOIN hive.canonical.repositories_current r ON d.repository_id = r.id
            WHERE d.repository_id_certainty IN (70, 85, 90)
            AND r.is_fork = FALSE
            AND r.is_archived = FALSE
            AND r.is_spammy_owner = FALSE
          ),
          direct_users AS (
            SELECT a.actor_id AS id
            FROM delta.snapshots.github_mysql_iam_abilities_abilities a
            INNER JOIN filtered_users u ON u.id = a.actor_id
            INNER JOIN publishing_repos r ON r.id = a.subject_id
            WHERE a.subject_type = 'Repository'
              AND a.action = 2
              AND a.actor_type = 'User'
          ),
          indirect_users AS (
            SELECT a.actor_id AS id
            FROM delta.snapshots.github_mysql_iam_abilities_abilities a
            INNER JOIN filtered_users u ON u.id = a.actor_id
            INNER JOIN delta.snapshots.github_mysql_iam_abilities_abilities p
              ON p.actor_type = a.subject_type
              AND p.actor_id = a.subject_id
            INNER JOIN publishing_repos r ON r.id = p.subject_id
            WHERE a.actor_type = 'User'
              AND a.subject_type IN ('Team', 'Organization')
              AND p.actor_type IN ('Team', 'Organization')
              AND p.subject_type = 'Repository'
              AND p.action = 2
          ),
          repo_owners AS (
            SELECT r.owner_id AS id
            FROM delta.snapshots.github_mysql1_repositories r
            INNER JOIN filtered_users u ON u.id = r.owner_id
            INNER JOIN publishing_repos n ON n.id = r.id
          )
        )
      end

      # Builds a raw query for trino that finds users who have administrate repositories that publish a package.
      #
      # This query isn't limited by time, as it would exclude users from repositories that only just recently met the
      # criteria threshold if their permissions were older than the lookback (which is short).
      #
      # Always use `filtered_users` instead of `delta.snapshots.github_mysql1_users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          SELECT DISTINCT id
          FROM (
            SELECT id FROM repo_owners
            UNION ALL
            SELECT id FROM direct_users
            UNION ALL
            SELECT id FROM indirect_users
          )
        )
      end
    end
  end
end
