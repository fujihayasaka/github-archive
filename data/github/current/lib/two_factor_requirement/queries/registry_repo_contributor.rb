# typed: true
# frozen_string_literal: true

module TwoFactorRequirement
  module Queries
    class RegistryRepoContributor < Base
      # if true, the discovery job will use the query to continuously discover users required for 2FA
      # if false, the discovery job will exclude it
      def steady_state_enabled?
        true
      end

      # Builds a raw query for trino that finds users who are registry repositories contributors limited by time.
      # Always use `filtered_users` instead of `delta.snapshots.github_mysql1_users`
      # `filtered_users` is pre-filtered to exclude users who have already been flagged for two factor requirement
      #
      # lookback_timestamp - A timestamp string for limiting discovery queries. If falsey, no date limitation should be applied.
      #
      # Returns a query string.
      def select_statement(lookback_timestamp: nil)
        %Q(
          (
            #{registry_repo_contributor_query(repo_ids: NPM_PACKAGE_REPO_IDS, lookback_timestamp: lookback_timestamp)}
          )
          UNION
          (
            #{registry_repo_contributor_query(repo_ids: PYPI_REPO_IDS, lookback_timestamp: lookback_timestamp)}
          )
          UNION
          (
            #{registry_repo_contributor_query(repo_ids: RUBY_GEMS_REPO_IDS, lookback_timestamp: lookback_timestamp)}
          )
        )
      end

      def registry_repo_contributor_query(repo_ids: nil, lookback_timestamp: nil)
        raise ArgumentError, "repo_ids is a required argument" if repo_ids.nil?

        %Q(
            SELECT DISTINCT(u.id) AS id
            FROM delta.snapshots.github_ballast_pushes p
            INNER JOIN filtered_users u on u.id = p.pusher_id
            WHERE p.repository_id in (#{repo_ids.join(',')})
              #{"AND (p.created_at > timestamp '#{lookback_timestamp}' OR p.updated_at > timestamp '#{lookback_timestamp}')" if lookback_timestamp}
        )
      end
    end
  end
end
