ALTER TABLE workflow_builds
ADD COLUMN started_at datetime(6) DEFAULT NULL after created_at,
ADD COLUMN event_time datetime(6) DEFAULT NULL after event,
ADD COLUMN rerun boolean DEFAULT false,
ADD COLUMN was_delayed boolean DEFAULT false;