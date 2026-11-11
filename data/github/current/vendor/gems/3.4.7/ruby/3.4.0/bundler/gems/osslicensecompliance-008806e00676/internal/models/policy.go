package models

import (
	"strings"

	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// This file contains structs and code common between the different types
// of policies (repository, organization, and enterprise).

// PolicyLevelToString converts a PolicyLevel enum to string.
func PolicyLevelToString(level proto.PolicyLevel) string {
	// The auto-generated String() method returns "POLICY_LEVEL_REPOSITORY"
	s := level.String()

	// Remove the "POLICY_LEVEL_" prefix
	s = strings.TrimPrefix(s, "POLICY_LEVEL_")

	// Convert to lowercase
	return strings.ToLower(s)
}
