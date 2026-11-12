package model

import (
	"testing"

	"github.com/stretchr/testify/require"
)

func TestTargetType_IsValid(t *testing.T) {
	validTargetTypes := []TargetType{
		Business,
		Global,
	}

	for _, targetType := range validTargetTypes {
		t.Run(targetType.String(), func(t *testing.T) {
			require.True(t, targetType.IsValid())
		})
	}

	// Test invalid target types
	invalidTargetTypes := []TargetType{
		"Organization",
		"InvalidType",
	}

	for _, targetType := range invalidTargetTypes {
		t.Run("invalid_"+string(targetType), func(t *testing.T) {
			require.False(t, targetType.IsValid())
		})
	}
}
