# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class PackageContributor < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      def cohort_ctes(lookback_timestamp: nil)
        %Q(
          , publishing_repos AS (
            SELECT DISTINCT d.repository_id as id
            FROM hive.snapshots_presto.dependency_graph_dg_packages d
            INNER JOIN hive.canonical.repositories_current r ON d.repository_id = r.id
            WHERE d.repository_id_certainty IN (70, 85, 90)
            AND r.is_fork = FALSE
            AND r.is_archived = FALSE
            AND r.is_spammy_owner = FALSE
          )
        )
      end

      # Builds a raw query for presto that finds users who have contributed to repositories that published a package.
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
            INNER JOIN publishing_repos pr ON pr.id = p.id
        )
      end
    end
  end
end
