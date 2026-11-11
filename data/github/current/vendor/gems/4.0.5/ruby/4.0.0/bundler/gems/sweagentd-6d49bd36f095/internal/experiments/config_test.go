package experiments

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestGetRandomizationUnitType(t *testing.T) {
	tests := []struct {
		name           string
		experimentName string
		expected       RandomizationUnitType
	}{
		{
			name:           "AutoModelExperiment uses tracking ID",
			experimentName: AutoModelExperiment,
			expected:       RandomizeByTrackingID,
		},
		{
			name:           "ModelCompareExperiment defaults to PR ID",
			experimentName: ModelCompareExperiment,
			expected:       RandomizeByPRID,
		},
		{
			name:           "AAExperiment defaults to PR ID",
			experimentName: AAExperiment,
			expected:       RandomizeByPRID,
		},
		{
			name:           "BlackbirdAblation defaults to PR ID",
			experimentName: BlackbirdAblation,
			expected:       RandomizeByPRID,
		},
		{
			name:           "BlackbirdTool defaults to PR ID",
			experimentName: BlackbirdTool,
			expected:       RandomizeByPRID,
		},
		{
			name:           "SearchAgentExperiment defaults to PR ID",
			experimentName: SearchAgentExperiment,
			expected:       RandomizeByPRID,
		},
		{
			name:           "MemoryExperiment defaults to PR ID",
			experimentName: MemoryExperiment,
			expected:       RandomizeByPRID,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := GetRandomizationUnitType(tt.experimentName)
			assert.Equal(t, tt.expected, result)
		})
	}
}
