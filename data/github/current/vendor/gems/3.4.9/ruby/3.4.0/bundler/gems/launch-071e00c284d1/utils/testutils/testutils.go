package testutils

import (
	"encoding/base64"
	"fmt"
	"strconv"
	"testing"

	circuit "github.com/rubyist/circuitbreaker"

	"github.com/github/launch/pkg/launchconfig"
)

func NoShort(t *testing.T) {
	if testing.Short() {
		t.Skip("skip because -short was selected")
	}
}

// EncodeGlobalID encodes a GlobalID; useful for transparency in tests.
// This should only be used for testing.
func EncodeGlobalID(typeName string, id int64) string {
	return EncodeGlobalIDString(typeName, strconv.FormatInt(id, 10))
}

func EncodeGlobalIDString(typeName, id string) string {
	s := fmt.Sprintf("0%d:%s%s", len(typeName), typeName, id)
	return base64.StdEncoding.EncodeToString([]byte(s))
}

// NewNoopBreaker uses a circuit.TripFunc that will always return false.
func NewNoopBreaker() *circuit.Breaker {
	return circuit.NewBreakerWithOptions(&circuit.Options{
		ShouldTrip: func(*circuit.Breaker) bool { return false },
	})
}

// SetAppMode sets the LAUNCH_MODE environment variable for a single test.
// It can't be used in conjunction with SetLaunchConfigEnv in the same test
// though, because it calls ResetConfig.
func SetAppMode(t *testing.T, env launchconfig.AppMode) {
	SetLaunchConfigEnv(t, EnvPair{"LAUNCH_MODE", env.String()})
}

// SetIsMultiTenant sets the LAUNCH_IS_MULTI_TENANT environment variable for a single test.
// It can't be used in conjunction with SetLaunchConfigEnv in the same test
// though, because it calls ResetConfig.
func SetIsMultiTenant(t *testing.T, isMultiTenant bool) {
	SetLaunchConfigEnv(t, EnvPair{"LAUNCH_IS_MULTI_TENANT", strconv.FormatBool(isMultiTenant)})
}

type EnvPair struct {
	Key   string
	Value string
}

// SetLaunchConfigEnv sets the environment variables for a single test.
// You pass them in as pairs, see SetAppMode above for an example.
// You can only use one of these methods in a single test, because they both
// call ResetConfig.
func SetLaunchConfigEnv(t *testing.T, pairs ...EnvPair) {
	t.Helper()
	launchconfig.ResetConfig()
	for _, p := range pairs {
		t.Setenv(p.Key, p.Value)
	}
	t.Cleanup(launchconfig.ResetConfig)
}
