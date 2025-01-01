package elasticsearch

// IndexConfig encapsulates properties related to an ElasticSearch index
type IndexConfig struct {
	name        string
	mapping     map[string]interface{}
	readAlias   string
	writeAlias  string
	mirrorAlias string
}

// The following section defines the (static) configuration we intend to use for our indices.

var orgLevelIndex = &IndexConfig{
	name:        "turboscan-13",
	mapping:     orglevelMapping,
	readAlias:   "turboscan-read",
	writeAlias:  "turboscan-write",
	mirrorAlias: "turboscan-mirror",
}

const caseInsensitiveNormalizer = "case_insensitive_keyword"

var caseInsensitiveKeywordPropertyMapping = map[string]interface{}{
	"type": "keyword",
	"fields": map[string]interface{}{
		"case_insensitive": map[string]interface{}{
			"type":       "keyword",
			"normalizer": caseInsensitiveNormalizer,
		},
	},
}

var orglevelMapping = map[string]interface{}{
	"mappings": map[string]interface{}{
		"doc": map[string]interface{}{
			"properties": map[string]interface{}{
				"alert_id": map[string]interface{}{
					"type": "long",
				},
				"number": map[string]interface{}{
					"type": "long",
				},
				"weight": map[string]interface{}{
					"type": "integer",
				},
				"sarif_identifier": caseInsensitiveKeywordPropertyMapping,
				"rule_name": map[string]interface{}{
					"type": "keyword",
				},
				"short_description": map[string]interface{}{
					"type":     "text",
					"analyzer": "english",
				},
				"full_description": map[string]interface{}{
					"type":     "text",
					"analyzer": "english",
				},
				"help": map[string]interface{}{
					"type":     "text",
					"analyzer": "english",
				},
				"tags": caseInsensitiveKeywordPropertyMapping,
				"severity": map[string]interface{}{
					"type": "keyword",
				},
				"tool": caseInsensitiveKeywordPropertyMapping,
				"tool_guid": map[string]interface{}{
					"type": "keyword",
				},
				"resolution": map[string]interface{}{
					"type": "keyword",
				},
				"resolved": map[string]interface{}{
					"type": "boolean",
				},
				"deleted": map[string]interface{}{
					"type": "boolean",
				},
				"fixed_on_default": map[string]interface{}{
					"type": "boolean",
				},
				"created_at": map[string]interface{}{
					"type": "date",
				},
				"updated_at": map[string]interface{}{
					"type": "date",
				},
				"insights_updated_at": map[string]interface{}{
					"type": "date",
				},
				"fixed_at": map[string]interface{}{
					"type": "date",
				},
				"resolved_at": map[string]interface{}{
					"type": "date",
				},
				"resolver_id": map[string]interface{}{
					"type": "keyword",
				},
				"canonical_id": map[string]interface{}{
					"type": "keyword",
				},
				"message": map[string]interface{}{
					"type":     "text",
					"analyzer": "english",
				},
				"file_path": map[string]interface{}{
					"type":     "text",
					"analyzer": "standard",
				},
				"classification": map[string]interface{}{
					"type": "keyword",
				},
				"repository_id": map[string]interface{}{
					"type": "keyword",
				},
				"owner_id": map[string]interface{}{
					"type": "keyword",
				},
				"code_scanning_enabled": map[string]interface{}{
					"type": "boolean",
				},
				"visibility": map[string]interface{}{
					"type": "keyword",
				},
				"has_links": map[string]interface{}{
					"type": "boolean",
				},
				"autofix_eligible": map[string]interface{}{
					"type": "boolean",
				},
				"autofix_state": map[string]interface{}{
					"type": "keyword",
				},
				"autofix_state_updated_at": map[string]interface{}{
					"type": "date",
				},
				"autofix_accepted": map[string]interface{}{
					"type": "boolean",
				},
				"security_campaign_id": map[string]interface{}{
					"type": "keyword",
				},
			},
		},
	},
}
