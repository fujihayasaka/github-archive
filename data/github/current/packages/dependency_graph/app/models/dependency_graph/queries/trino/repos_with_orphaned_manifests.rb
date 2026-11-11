# typed: true
# frozen_string_literal: true

module DependencyGraph
  module Queries
    module Trino
      class ReposWithOrphanedManifests < Base

        attr_reader :cursor, :limit, :query

        # Identifies repositories that are inactive and eligible for disabling the dependency graph feature.
        #
        # Parameters:
        #
        # cursor - The starting manifest ID for the query, typically used for pagination.
        #          Defaults to 0, which starts from the beginning.
        #
        # limit - The maximum number of manifest IDs to return in the result set.
        #         Can not exceed the TRINO_QUERY_RESULTS_LIMIT constant.
        sig { params(cursor: Integer, limit: T.nilable(Integer)).void }
        def initialize(cursor: 0, limit: nil)
          @cursor = cursor
          @limit = limit
          # we build the query after all the other instance variables are set
          @query = build_query
        end

        # The name of the query. This is used for tracking and reporting purposes.
        sig { returns(String) }
        def query_name
          "repos_with_orphaned_manifests"
        end

        private

        # Constructs the SQL query to identify orphaned manifests.
        sig { override.returns(String) }
        def build_query
          <<~SQL
            SELECT DISTINCT r.github_repository_id AS repository_id
            FROM delta.snapshots.dependency_graph_dg_manifests m
            INNER JOIN delta.snapshots.dependency_graph_dg_repositories r
                ON m.repository_id = r.id
            LEFT JOIN delta.snapshots.github_mysql1_repositories ghr
                ON r.github_repository_id = ghr.id
            LEFT JOIN delta.snapshots.github_security_products_enablement_repository_security_settings s
                ON ghr.id = s.repository_id
                AND s.feature = 1 AND s.state = 1
            WHERE s.repository_id IS NULL
            AND r.github_repository_id > #{@cursor}
            ORDER BY r.github_repository_id ASC
            #{limit_query_string(@limit)}
          SQL
        end
      end
    end
  end
end
