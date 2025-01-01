# typed: true
# frozen_string_literal: true

module DependencyGraph
  module Queries
    module Trino
      class InactiveReposCount < InactiveRepos

        # The name of the query. This is used for tracking and reporting purposes.
        sig { override.returns(String) }
        def query_name
          "inactive_repos_count"
        end

        private

        # Constructs the SQL query to count inactive repositories.
        sig { override.returns(String) }
        def build_query
          <<~SQL
            WITH
            #{low_stars_repos(max_stars: @max_stars)},
            #{inactive_repos(max_years: @max_years)},
            #{repos_with_packages},
            #{repos_with_dependabot},
            #{repos_with_dg_enabled }
            #{select_statement(skip_enterprise: @skip_enterprise)}
          SQL
        end

        # SQL statement to count repository IDs that are inactive and eligible for disabling the dependency graph feature.
        #
        # The `cursor` parameter is accepted for interface compatibility but is not used in this implementation.
        sig { override.params(cursor: Integer, skip_enterprise: T::Boolean).returns(String) }
        def select_statement(cursor: 0, skip_enterprise: true)
          <<~SQL
            SELECT
              COUNT(r.id) AS inactive_repository_count
            FROM
              hive.canonical.repositories_current r
            JOIN
              repos_with_dg_enabled dg on r.id = dg.repository_id
            JOIN
              low_star_repos l ON r.id = l.id
            JOIN
              inactive_repos i ON r.id = i.id
            WHERE
              r.id NOT IN (SELECT repository_id FROM repos_with_packages)
              AND r.id NOT IN (SELECT target_id FROM repos_with_dependabot)
              #{skip_enterprise_clause if skip_enterprise}
          SQL
        end
      end
    end
  end
end
