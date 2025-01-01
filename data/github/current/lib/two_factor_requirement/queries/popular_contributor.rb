# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class PopularContributor < Base
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
          )
        )
      end

      # Builds a raw query for presto that finds users who have contributed to popular repositories.
      #
      # This query isn't limited by time, as it would exclude users from repositories that only just recently met the
      # criteria threshold if their contributions were older than the lookback (which is short).
      #
      # Always use `filtered_users` instead of `hive.snapshots_presto.users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          SELECT distinct(u.id) AS id
          FROM delta.snapshots.github_ballast_pushes p
            INNER JOIN filtered_users u on u.id = p.pusher_id
            INNER JOIN popular_repositories pr ON pr.id = p.id
        )
      end
    end
  end
end
