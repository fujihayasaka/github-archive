-- Query to identify orphaned manifest entry IDs for removal by the `delete_orphaned_manifest_entries.rb` transition.
-- Orphaned manifest entries are defined as those associated with manifests that no longer exist.
-- Execute on Trino; export results as CSV files in this directory.
SELECT DISTINCT me.id
From delta.snapshots.dependency_graph_dg_manifest_entries me
         LEFT JOIN delta.snapshots.dependency_graph_dg_manifests m
                   ON me.manifest_id = m.id
WHERE m.id is NULL ORDER BY me.id ASC;
