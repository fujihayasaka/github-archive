# typed: true
# frozen_string_literal: true

module DependencyGraph
  module Queries
    module Trino
      class ReposWithOrphanedManifestsCount < ReposWithOrphanedManifests

        # The name of the query. This is used for tracking and reporting purposes.
        sig { override.returns(String) }
        def query_name
          "repos_with_orphaned_manifests_count"
        end

        private

        # Constructs the SQL query to count orphaned manifests.
        sig { override.returns(String) }
        def build_query
          <<~SQL
            SELECT COUNT(distinct r.github_repository_id) AS missing_count
            FROM delta.snapshots.dependency_graph_dg_manifests m
            INNER JOIN delta.snapshots.dependency_graph_dg_repositories r
                ON m.repository_id = r.id
            LEFT JOIN delta.snapshots.github_mysql1_repositories ghr
                ON r.github_repository_id = ghr.id
            LEFT JOIN delta.snapshots.github_security_products_enablement_repository_security_settings s
                ON ghr.id = s.repository_id
                AND s.feature = 1 AND s.state = 1
            WHERE s.repository_id IS NULL
          SQL
        end
      end
    end
  end
end
