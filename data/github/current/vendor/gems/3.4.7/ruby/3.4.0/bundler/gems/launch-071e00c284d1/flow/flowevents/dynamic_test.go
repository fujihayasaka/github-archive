package flowevents

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestExtractDynamicWorkflowFilePath(t *testing.T) {
	tests := []struct {
		path           string
		wantIntegrator string
		wantSlug       string
		wantOk         bool
	}{
		{
			path:           "dynamic/testintegration/testslug",
			wantIntegrator: "testintegration",
			wantSlug:       "testslug",
			wantOk:         true,
		},
		{
			path:           "notdynamic/testintegration/testslug",
			wantIntegrator: "",
			wantSlug:       "",
			wantOk:         false,
		},
	}
	for _, tt := range tests {
		t.Run(tt.path, func(t *testing.T) {
			gotIntegrator, gotSlug, gotOk := ExtractDynamicWorkflowFilePath(tt.path)
			require.Equal(t, tt.wantIntegrator, gotIntegrator)
			require.Equal(t, tt.wantSlug, gotSlug)
			require.Equal(t, tt.wantOk, gotOk)
		})
	}
}
