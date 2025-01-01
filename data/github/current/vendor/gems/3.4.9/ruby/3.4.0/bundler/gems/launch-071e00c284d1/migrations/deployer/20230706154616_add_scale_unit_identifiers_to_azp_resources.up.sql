ALTER TABLE `azp_resources`
ADD COLUMN (
  `pipelines_scale_unit_id` binary(16) DEFAULT NULL,
  `artifact_cache_scale_unit_id` binary(16) DEFAULT NULL,
  `runner_scale_unit_id` binary(16) DEFAULT NULL
);