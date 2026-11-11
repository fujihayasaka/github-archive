ALTER TABLE ds_snapshots ADD COLUMN snapshot_type ENUM('complete', 'incremental') NOT NULL DEFAULT 'complete';
