# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class PopularAdmin < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      def cohort_ctes(lookback_timestamp: nil)
        %Q(
        , release_counts AS (
            SELECT repository_id, SUM(downloads) AS total_repo_downloads
            FROM hive.snapshots_presto.release_assets
            GROUP BY repository_id
          ),
          repository_popularity AS (
            SELECT repos.id AS repository_id,
                  COALESCE(release_counts.total_repo_downloads, 0) AS total_repo_downloads,
                  repos.num_watchers,
                  repos.num_stars,
                  repos.num_public_forks,
                  (COALESCE(release_counts.total_repo_downloads, 0) + repos.num_watchers + repos.num_stars + repos.num_public_forks) AS popularity
            FROM hive.canonical.repositories_current AS repos
            LEFT JOIN release_counts
              ON repos.id = release_counts.repository_id
            WHERE repos.is_fork = FALSE
            AND repos.is_archived = FALSE
            AND repos.is_spammy_owner = FALSE
          ),
          popular_repositories AS (
            SELECT repository_id as id
            FROM repository_popularity
            WHERE popularity > 50
          ),
          direct_users AS (
            SELECT a.actor_id AS id
            FROM hive.snapshots_presto.abilities a
            INNER JOIN filtered_users u ON u.id = a.actor_id
            INNER JOIN popular_repositories r ON r.id = a.subject_id
            WHERE a.subject_type = 'Repository'
              AND a.action = 2
              AND a.actor_type = 'User'
          ),
          indirect_users AS (
            SELECT a.actor_id AS id
            FROM hive.snapshots_presto.abilities a
            INNER JOIN filtered_users u ON u.id = a.actor_id
            INNER JOIN hive.snapshots_presto.abilities p
              ON p.actor_type = a.subject_type
              AND p.actor_id = a.subject_id
            INNER JOIN popular_repositories r ON r.id = p.subject_id
            WHERE a.actor_type = 'User'
              AND a.subject_type IN ('Team', 'Organization')
              AND p.actor_type IN ('Team', 'Organization')
              AND p.subject_type = 'Repository'
              AND p.action = 2
          ),
          repo_owners AS (
            SELECT r.owner_id AS id
            FROM hive.snapshots_presto.repositories r
            INNER JOIN filtered_users u ON u.id = r.owner_id
            INNER JOIN popular_repositories n ON n.id = r.id
          )
        )
      end

      # Builds a raw query for presto that finds users who administrate popular repositories.
      #
      # This query isn't limited by time, as it would exclude users from repositories that only just recently met the
      # criteria threshold if their permissions were older than the lookback (which is short).
      #
      # Always use `filtered_users` instead of `hive.snapshots_presto.users`
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
