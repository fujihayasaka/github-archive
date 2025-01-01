package config

import (
	"fmt"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestMySQLWriteThrottlingEnabled(t *testing.T) {
	for _, tc := range []struct {
		env               string
		throttlingEnabled bool
		expected          bool
	}{
		{"production", true, true},
		{"production", false, false},
		{"production/canary", true, true},
		{"production/canary", false, false},
		{"development", true, false},
		{"development", false, false},
	} {
		name := fmt.Sprintf("%s with throttling enabled? %t", tc.env, tc.throttlingEnabled)
		t.Run(name, func(t *testing.T) {
			cfg := &CommonConfig{
				DeploymentEnvironment:  tc.env,
				FrenoThrottlingEnabled: tc.throttlingEnabled,
			}
			assert.Equal(t, tc.expected, cfg.MySQLWriteThrottlingEnabled())
		})
	}
}

func TestHMACAuthRequired(t *testing.T) {
	for _, tc := range []struct {
		isProxima bool
		dotcomCI  bool
		expected  bool
	}{
		// always disabled in Proxima
		{isProxima: true, dotcomCI: true, expected: false},
		{isProxima: true, dotcomCI: false, expected: false},
		// always disabled in Dotcom CI
		{isProxima: true, dotcomCI: true, expected: false},
		{isProxima: false, dotcomCI: true, expected: false},
		// enabled outside of Proxima and Dotcom CI
		{isProxima: false, dotcomCI: false, expected: true},
	} {
		testName := fmt.Sprintf("required=%t,proxima=%t,dotcom_ci=%t", tc.expected, tc.isProxima, tc.dotcomCI)
		t.Run(testName, func(t *testing.T) {
			cfg := &CommonConfig{
				DotcomCIMode: tc.dotcomCI,
				IsProxima:    tc.isProxima,
			}
			assert.Equal(t, tc.expected, cfg.HMACAuthRequired())
		})
	}
}
