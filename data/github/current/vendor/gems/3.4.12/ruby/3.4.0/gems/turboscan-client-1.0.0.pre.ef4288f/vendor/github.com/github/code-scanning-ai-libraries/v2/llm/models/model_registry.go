// Package models provide utilities for reading the capabilities of LLM models, and other related model utilities.
package models

import (
	"embed"
	"encoding/json"
	"sync"

	"github.com/github/code-scanning-ai-libraries/v2/errors"
)

// ModelRegistry provides access to model capabilities by different identifiers
type ModelRegistry struct {
	models    map[string]*ModelEntry
	initError errors.LLMError
}

var globalRegistry *ModelRegistry
var initRegistryOnce sync.Once

// modelsFS is an embedded filesystem containing the models.json file.
//
//go:embed data/models.json
var modelsFS embed.FS

// GetRegistry returns the global model registry, initializing if needed
func GetRegistry() (*ModelRegistry, errors.LLMError) {
	initRegistryOnce.Do(func() {
		globalRegistry = &ModelRegistry{ //nolint:exhaustruct // Intentionally not initializing all fields
			models: make(map[string]*ModelEntry),
		}

		data, err := modelsFS.ReadFile("data/models.json")
		if err != nil {
			globalRegistry.initError = errors.GenericFatalError{Err: err}
			return
		}

		var modelList ModelList
		if err := json.Unmarshal(data, &modelList); err != nil {
			globalRegistry.initError = errors.GenericFatalError{Err: err}
			return
		}

		// Build registry maps
		for i := range modelList.Data {
			model := &modelList.Data[i]
			globalRegistry.models[model.ID] = model
		}
	})

	return globalRegistry, globalRegistry.initError
}

// GetModel finds the model capabilities by any supported identifier
func (r *ModelRegistry) GetModel(modelName string) (*ModelEntry, bool) {
	// Check if this is an exact model ID
	model, found := r.models[modelName]
	if found {
		return model, true
	}

	// No match found
	return nil, false
}
