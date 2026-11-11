package snapshots

import (
	"context"
	"testing"

	"github.com/github/dependency-snapshots-api/internal/interfaces"
	"github.com/stretchr/testify/assert"
)

func TestValidateDetectorName(t *testing.T) {
	tests := []struct {
		name         string
		detectorName string
		expectError  bool
	}{
		{
			name:         "valid detector name",
			detectorName: "test-detector",
			expectError:  false,
		},
		{
			name:         "dependabot detector name should fail",
			detectorName: "dependabot",
			expectError:  true,
		},
		{
			name:         "case insensitive - Dependabot should fail",
			detectorName: "Dependabot",
			expectError:  true,
		},
		{
			name:         "case insensitive - DEPENDABOT should fail",
			detectorName: "DEPENDABOT",
			expectError:  true,
		},
		{
			name:         "case insensitive - DependaBot should fail",
			detectorName: "DependaBot",
			expectError:  true,
		},
		{
			name:         "empty detector name should pass",
			detectorName: "",
			expectError:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			snapshot := &interfaces.Snapshot{
				Detector: &interfaces.DetectorMetadata{
					Name: tt.detectorName,
				},
			}

			err := ValidateDetectorName(context.Background(), snapshot)

			if tt.expectError {
				assert.Error(t, err)
				assert.Contains(t, err.Error(), "reserved for internal services")
			} else {
				assert.NoError(t, err)
			}
		})
	}
}

func TestValidateDetectorNameWithNilDetector(t *testing.T) {
	snapshot := &interfaces.Snapshot{
		Detector: nil,
	}

	err := ValidateDetectorName(context.Background(), snapshot)
	assert.NoError(t, err, "Should not error when detector is nil")
}
