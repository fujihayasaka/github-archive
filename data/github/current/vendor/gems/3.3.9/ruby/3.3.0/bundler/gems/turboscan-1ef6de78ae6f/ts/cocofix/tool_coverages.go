package cocofix

import (
	_ "embed"
	"encoding/json"
	"sync"
)

//go:embed .tool_coverages.json
var content []byte

type ToolCoverages map[string]map[string][]string

var (
	toolCoverageMap  ToolCoverages
	initToolCoverage sync.Once
)

func LoadToolCoverages() ToolCoverages {
	initToolCoverage.Do(func() {
		_ = json.Unmarshal(content, &toolCoverageMap)
	})

	return toolCoverageMap
}
