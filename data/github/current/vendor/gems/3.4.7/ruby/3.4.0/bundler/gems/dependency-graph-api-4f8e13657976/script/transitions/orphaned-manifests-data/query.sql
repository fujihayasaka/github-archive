-- Query to identify orphaned manifest IDs for removal by the `destroy_orphaned_manifests.rb` transition.
-- Orphaned manifests are defined as those associated with repositories that no longer exist.
-- Execute on Trino; export results as CSV files in this directory.
SELECT DISTINCT m.id
FROM delta.snapshots.dependency_graph_dg_manifests m
LEFT JOIN delta.snapshots.dependency_graph_dg_repositories r
    ON m.repository_id = r.id
WHERE r.id IS NULL ORDER BY m.id ASC;