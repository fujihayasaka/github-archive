package config

import "sync"

type Model struct {
	WorkloadWeights           map[string]float64
	RPSLimit, RPSBoostedLimit float64 // requests per second
}

// The weights are arbitrary, but the ratios are important.
// For simplicity-sake, we add up the weights to 100 per model.

// Define the available workloads
const (
	SecretScanningIncremental       = "secret-scanning-incremental"
	SecretScanningIncrementalSlow   = "secret-scanning-incremental-slow"
	SecretScanningBackfill          = "secret-scanning-backfill"
	SecretScanningNoopBackfill      = "secret-scanning-noop-backfill"
	CodeScanningAutofixHighPriority = "code-scanning-autofix-high-priority"
	CodeScanningAutofixLowPriority  = "code-scanning-autofix-low-priority"
	CodeQualityHighPriority         = "code-quality-high-priority"
	CodeQualityLowPriority          = "code-quality-low-priority"
)

var (
	miniModelWorkloadWeights = map[string]float64{
		SecretScanningIncremental:     50,
		SecretScanningIncrementalSlow: 25,
		SecretScanningBackfill:        20,
		SecretScanningNoopBackfill:    5,
	}
	largeModelWorkloadWeights = map[string]float64{
		SecretScanningIncremental:       30,
		SecretScanningIncrementalSlow:   15,
		SecretScanningBackfill:          5,
		CodeScanningAutofixHighPriority: 35,
		CodeScanningAutofixLowPriority:  5,
		SecretScanningNoopBackfill:      5,
		CodeQualityHighPriority:         3,
		CodeQualityLowPriority:          2,
	}
)

// All of these limits are copied directly from the github/copilot-api repository
// These values can be found under the "ghas-secret-scanning" integration in
// `cmd/http/config/integration_map.go`
const (
	miniModelRPS        = 250
	miniModelBoostedRPS = 280

	largeModelRPS        = 18
	largeModelBoostedRPS = 24
)

var (
	miniModelConfig = Model{
		WorkloadWeights: miniModelWorkloadWeights,
		RPSLimit:        miniModelRPS,
		RPSBoostedLimit: miniModelBoostedRPS,
	}
	largeModelConfig = Model{
		WorkloadWeights: largeModelWorkloadWeights,
		RPSLimit:        largeModelRPS,
		RPSBoostedLimit: largeModelBoostedRPS,
	}
)

const (
	GPT4oMini = "gpt-4o-mini"
	GPT4o     = "gpt-4o"
	GPT4Dot1  = "gpt-4.1"
	GPT5Mini  = "gpt-5-mini"
	GPT5Nano  = "gpt-5-nano"
	// when adding a new model here, please also update allModelNames
)

var allModelNames = []string{
	GPT4oMini,
	GPT4o,
	GPT4Dot1,
	GPT5Mini,
	GPT5Nano,
}

func IsLargeModel(name string) bool {
	switch name {
	case GPT4o, GPT4Dot1:
		return true
	default:
		return false
	}
}

var Models = sync.OnceValue(func() map[string]Model {
	models := make(map[string]Model, len(allModelNames))
	for _, name := range allModelNames {
		if IsLargeModel(name) {
			models[name] = largeModelConfig
		} else {
			models[name] = miniModelConfig
		}
	}
	return models
})
