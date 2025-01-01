# typed: true
# frozen_string_literal: true

module DependencyGraph
  module Queries
    module Trino
      class InactiveRepos < Base

        # Check https://data.githubapp.com/warehouse/hive/canonical/plans_current#!overview-tab for plan IDs.
        ENTERPRISE_PLAN_IDS = [4, 5, 6].freeze

        attr_reader :max_stars, :max_years, :skip_enterprise, :cursor, :limit, :query

        # Identifies repositories that are inactive and eligible for disabling the dependency graph feature.
        #
        # Parameters:
        # max_stars - The maximum number of stars a repository can have to be considered inactive.
        #             Defaults to 1, meaning only repositories without any stars are considered inactive.
        #
        # max_years - The maximum number of years a repository can be inactive to qualify as inactive.
        #             Defaults to 10 years, providing a lenient threshold for inactivity.
        #
        # skip_enterprise - A boolean flag indicating whether to skip repositories with enterprise plans.
        #
        # cursor - The starting repository ID for the query, typically used for pagination.
        #          Defaults to 0, which starts from the beginning.
        #
        # limit - The maximum number of repository IDs to return in the result set.
        #         Can not exceed the TRINO_QUERY_RESULTS_LIMIT constant.
        sig { params(max_stars: Integer, max_years: Integer, skip_enterprise: T::Boolean, cursor: Integer, limit: T.nilable(Integer)).void }
        def initialize(max_stars: 1, max_years: 10, skip_enterprise: true, cursor: 0, limit: nil)
          @max_stars = max_stars
          @max_years = max_years
          @skip_enterprise = skip_enterprise
          @cursor = cursor
          @limit = limit
          # we build the query after all the other instance variables are set
          @query = build_query
        end

        # The name of the query. This is used for tracking and reporting purposes.
        sig { returns(String) }
        def query_name
          "inactive_repos"
        end

        private

        # Constructs the SQL query to identify inactive repositories.
        sig { override.returns(String) }
        def build_query
          <<~SQL
            WITH
            #{low_stars_repos(max_stars: @max_stars)},
            #{inactive_repos(max_years: @max_years)},
            #{repos_with_packages},
            #{repos_with_dependabot},
            #{repos_with_dg_enabled }
            #{select_statement(cursor: @cursor, skip_enterprise: @skip_enterprise)}
            #{limit_query_string(@limit)}
          SQL
        end

        # SQL subquery to identify repositories with low stars.
        sig { params(max_stars: Integer).returns(String) }
        def low_stars_repos(max_stars: 1)
          <<~SQL
            low_star_repos AS (
              SELECT DISTINCT id
              FROM hive.canonical.repositories_current
              WHERE num_stars < #{max_stars}
            )
          SQL
        end

        # SQL subquery to identify inactive repositories based on the last push date.
        sig { params(max_years: Integer).returns(String) }
        def inactive_repos(max_years: 10)
          <<~SQL
            inactive_repos AS (
              SELECT DISTINCT id
              FROM delta.snapshots.github_mysql1_repositories
              WHERE pushed_at < date_add('day', -365 * #{max_years}, current_date)
            )
          SQL
        end

        # SQL subquery to identify repositories with packages in DG-API database.
        sig { returns(String) }
        def repos_with_packages
          <<~SQL
            repos_with_packages AS (
              SELECT DISTINCT repository_id
              FROM delta.snapshots.dependency_graph_dg_package_versions
              WHERE repository_id IS NOT NULL
            )
          SQL
        end

        # SQL subquery to identify repositories with at least one of the specified Dependabot configurations.
        sig { returns(String) }
        def repos_with_dependabot
          <<~SQL
            repos_with_dependabot AS (
              SELECT DISTINCT target_id
              FROM delta.snapshots.github_mysql1_configuration_entries
              WHERE target_type = 'Repository' AND
                name IN (
                  'dependabot.config_file.enabled',
                  'dependency_vulnerability_alerts.enabled',
                  'repository_dependency_updates.vulnerabilities.enabled'
                )
            )
          SQL
        end

        # SQL subquery to identify repositories with the dependency graph feature enabled.
        sig { returns(String) }
        def repos_with_dg_enabled
          <<~SQL
            repos_with_dg_enabled AS (
              WITH dg_configs AS (
                SELECT
                  target_id,
                  SUM(CASE WHEN name = 'dependency_graph.enabled' THEN 1 ELSE 0 END) AS enabled,
                  SUM(CASE WHEN name = 'dependency_graph.disabled' THEN 1 ELSE 0 END) AS disabled
                FROM delta.snapshots.github_mysql1_configuration_entries
                WHERE target_type = 'Repository' AND
                  name IN ('dependency_graph.enabled', 'dependency_graph.disabled')
                  GROUP BY 1
              )
              SELECT DISTINCT r.id
              FROM hive.canonical.repositories_current r
              LEFT JOIN dg_configs ON r.id = dg_configs.target_id
              WHERE
                r.is_public IS NOT NULL
                AND (
                  (r.is_public = TRUE AND dg_configs.disabled = 0)
                  OR (r.is_public = TRUE AND dg_configs.disabled IS NULL)
                  OR (r.is_public = FALSE AND dg_configs.enabled > 0)
                )
            )
          SQL
        end

        # Constructs the skip enterprise clause for the SQL query.
        sig { returns(String) }
        def skip_enterprise_clause
          "AND r.owner_plan_id NOT IN (#{ENTERPRISE_PLAN_IDS.join(', ')})"
        end

        # SQL statement to select repository IDs that are inactive and eligible for disabling the dependency graph feature.
        sig { params(cursor: Integer, skip_enterprise: T::Boolean).returns(String) }
        def select_statement(cursor: 0, skip_enterprise: true)
          <<~SQL
            SELECT
              r.id AS repository_id
            FROM
              hive.canonical.repositories_current r
            JOIN
              repos_with_dg_enabled dg on r.id = dg.id
            JOIN
              low_star_repos l ON r.id = l.id
            JOIN
              inactive_repos i ON r.id = i.id
            WHERE
              r.id NOT IN (SELECT repository_id FROM repos_with_packages)
              AND r.id NOT IN (SELECT target_id FROM repos_with_dependabot)
              AND r.id > #{cursor}
              #{skip_enterprise_clause if skip_enterprise}
            ORDER BY repository_id ASC
          SQL
        end
      end
    end
  end
end
