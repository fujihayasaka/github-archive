package migrations

var _ = Transitions.Step(1000).Batched("ts_rules", `
UPDATE ts_rules FORCE INDEX(PRIMARY) SET updated_at = NOW(), hash = (
  SELECT
	UNHEX(SHA2(CONCAT(
	  SHA2(IFNULL(name, ''), 256),
	  SHA2(IFNULL(short_description, ''), 256),
	  SHA2(IFNULL(full_description, ''), 256),
	  SHA2(IFNULL(help_uri, ''), 256),
	  SHA2(IFNULL(help, ''), 256),
	  SHA2(severity_level, 256),
	  SHA2(IFNULL(security_severity, ''), 256),
	  SHA2(precision_level, 256),
	  SHA2(query_uri, 256),
	  SHA2(IFNULL(GROUP_CONCAT(UNHEX(SHA2(ts_rule_tags.tag, 256)) ORDER BY ts_rule_tags.tag ASC SEPARATOR ''), ''), 256)
	), 256))
  FROM ts_rule_tags WHERE ts_rule_tags.rule_id = ts_rules.id
)
WHERE id BETWEEN ? AND ?
AND hash IS NULL`)
