package config

const (
	GPT35 = "gpt-3.5-turbo"
	GPT4  = "gpt-4"
)

// Define the available workloads
const (
	SecretScanningIncremental       = "secret-scanning-incremental"
	SecretScanningBackfill          = "secret-scanning-backfill"
	CodeScanningAutofixHighPriority = "code-scanning-autofix-high-priority"
	CodeScanningAutofixLowPriority  = "code-scanning-autofix-low-priority"
)

func GetWorkloadWeightsFor(m string) map[string]float64 {
	switch m {
	case GPT35:
		return map[string]float64{
			SecretScanningIncremental: 20,
			SecretScanningBackfill:    5,
		}
	case GPT4:
		return map[string]float64{
			SecretScanningIncremental:       20,
			SecretScanningBackfill:          5,
			CodeScanningAutofixHighPriority: 20,
			CodeScanningAutofixLowPriority:  5,
		}
	}

	return map[string]float64{}
}
