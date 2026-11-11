// Package gateevaluation contains the functionality to evaluate non-actor gates.
package gateevaluation

import (
	"hash/crc32"
	randv2 "math/rand/v2"
	"slices"
	"strings"

	"github.com/github/feature-management-client-go/vexi/v2/featureflag"
)

// Service holds all the configuration for the gate evaluation service.
type Service struct{}

// EvaluateBooleanGate returns the value of the boolean gate.
func (s Service) EvaluateBooleanGate(ff featureflag.FeatureFlag) bool {
	return ff.BooleanGate
}

// EvaluatePercentageOfCallsGate generates a random float number and returns true if this number is less than the gate value divided by 100, essentially enabling a feature flag for a certain percentage of calls.
func (s Service) EvaluatePercentageOfCallsGate(ff featureflag.FeatureFlag) bool {
	return randv2.Float64() < (ff.PercentageOfCalls / 100) //nolint:gosec // This is used to keep it consistent with how Flipper evalutes the percentage of calls gate.
}

// EvaluatePercentageOfActorsGate calculates and compares the CRC32 checksum of a concatenated string (made up of a feature flag name and sorted actor strings) with a scaled value of the gate, returning true if the checksum is less, and false otherwise.
func (s Service) EvaluatePercentageOfActorsGate(ff featureflag.FeatureFlag, actors ...string) bool {
	const scalingFactor = 1000

	if len(actors) == 0 {
		return false
	}

	slices.Sort(actors)

	id := ff.Name + strings.Join(actors, "")

	bkt := int(crc32.ChecksumIEEE([]byte(id))) % (100 * scalingFactor)
	return bkt < int(ff.PercentageOfActors)*scalingFactor
}
