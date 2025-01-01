package models

import (
	"embed"
	"encoding/json"
	"strings"
	"sync"

	"github.com/github/codeml-autofix/go/pkg/autofix"
)

// ModelRegistry provides access to model capabilities by different identifiers
type ModelRegistry struct {
	models      map[string]*ModelEntry
	flavorToID  map[string]string
	initialized bool
	initOnce    sync.Once
	initError   autofix.AutofixError
}

var globalRegistry *ModelRegistry

// modelsFS is an embedded filesystem containing the models.json file.
//
//go:embed data/models.json
var modelsFS embed.FS

// GetRegistry returns the global model registry, initializing if needed
func GetRegistry() (*ModelRegistry, autofix.AutofixError) {
	if globalRegistry != nil && globalRegistry.initialized {
		return globalRegistry, globalRegistry.initError
	}

	globalRegistry = &ModelRegistry{ //nolint:exhaustruct
		models:     make(map[string]*ModelEntry),
		flavorToID: make(map[string]string),
	}

	globalRegistry.initOnce.Do(func() {
		data, err := modelsFS.ReadFile("data/models.json")
		if err != nil {
			globalRegistry.initError = autofix.RetryableError{Err: err}
			return
		}

		var modelList ModelList
		if err := json.Unmarshal(data, &modelList); err != nil {
			globalRegistry.initError = autofix.LogicError{Err: err}
			return
		}

		// Build registry maps
		for i := range modelList.Data {
			model := &modelList.Data[i]
			globalRegistry.models[model.ID] = model

			// Add standard flavor mappings
			globalRegistry.addFlavorMappings(model)
		}

		globalRegistry.initialized = true
	})

	return globalRegistry, globalRegistry.initError
}

// GetModel finds the model capabilities by any supported identifier
func (r *ModelRegistry) GetModel(modelName string) (*ModelEntry, bool) {
	// Check if this is an exact model ID
	if model, found := r.GetModelByID(modelName); found {
		return model, true
	}

	// Check if this is a standard flavor name
	if model, found := r.GetModelByFlavor(modelName); found {
		return model, true
	}

	// Handle common prefixes
	prefixes := []string{"capi-", "capi-dev-", "capi-prod-", "dev-", "prod-"}
	for _, prefix := range prefixes {
		if strings.HasPrefix(modelName, prefix) {
			trimmed := strings.TrimPrefix(modelName, prefix)
			if model, found := r.GetModelByID(trimmed); found {
				return model, true
			}
			if model, found := r.GetModelByFlavor(trimmed); found {
				return model, true
			}
		}
	}

	// Handle substring matching for common models
	modelNameLower := strings.ToLower(modelName)
	substrings := map[string]string{
		"4o-mini":           "gpt-4o-mini",
		"4o":                "gpt-4o",
		"claude-3.5-sonnet": "claude-3.5-sonnet",
		"claude":            "claude-3.5-sonnet",
		"gemini":            "gemini-1.5-pro",
		"o1-mini":           "o1-mini",
		"o1-ga":             "o1",
		"o1":                "o1",
		"4.1":               "gpt-4.1",
		"o3":                "o3",
		"o4-mini":           "o4-mini",
	}

	for substr, id := range substrings {
		if strings.Contains(modelNameLower, substr) {
			// Handle special cases to avoid false matches
			if substr == "4o" && strings.Contains(modelNameLower, "4o-mini") {
				continue // Don't match "4o" when it's part of "4o-mini"
			}
			if substr == "o1" && strings.Contains(modelNameLower, "o1-mini") {
				continue // Don't match "o1" when it's part of "o1-mini"
			}

			if model, found := r.GetModelByID(id); found {
				return model, true
			}
		}
	}

	// No match found
	return nil, false
}

// addFlavorMappings adds common flavor variations for models
func (r *ModelRegistry) addFlavorMappings(model *ModelEntry) {
	id := model.ID

	prefixes := []string{"", "dev-", "prod-", "capi-dev-", "capi-prod-"}

	switch {
	case strings.Contains(id, "gpt-4o-mini"):
		for _, prefix := range prefixes {
			r.flavorToID[prefix+"gpt-4o-mini"] = id
			r.flavorToID[prefix+"4o-mini"] = id
		}
	case strings.Contains(id, "gpt-4o"):
		for _, prefix := range prefixes {
			r.flavorToID[prefix+"gpt-4o"] = id
			r.flavorToID[prefix+"4o"] = id
		}
	case strings.Contains(id, "claude-3.5-sonnet"):
		for _, prefix := range prefixes {
			r.flavorToID[prefix+"claude-3.5-sonnet"] = id
			r.flavorToID[prefix+"claude-sonnet"] = id
		}
	}

	if model.Vendor == "Anthropic" {
		r.flavorToID["claude"] = id
	}
}

// GetModelByID returns a model by ID
func (r *ModelRegistry) GetModelByID(id string) (*ModelEntry, bool) {
	model, found := r.models[id]
	return model, found
}

// GetModelByFlavor returns a model by flavor name
func (r *ModelRegistry) GetModelByFlavor(flavor string) (*ModelEntry, bool) {
	id, found := r.GetModelIDFromFlavor(flavor)
	if !found {
		return nil, false
	}
	return r.GetModelByID(id)
}

// GetModelIDFromFlavor returns the canonical model ID for a flavor
func (r *ModelRegistry) GetModelIDFromFlavor(flavor string) (string, bool) {
	id, ok := r.flavorToID[strings.ToLower(flavor)]
	return id, ok
}
