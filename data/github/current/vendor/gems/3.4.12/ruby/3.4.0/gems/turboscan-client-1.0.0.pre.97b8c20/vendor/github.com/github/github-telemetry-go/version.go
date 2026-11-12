// Package version provides runtime version info for this module.
package version

import (
	"runtime/debug"
	"strings"
)

// GlobalSDKName is the name of this library.
const GlobalSDKName = "github-telemetry-go"

// GlobalSDKVersion is the version of this library.
var GlobalSDKVersion = func() string {
	// This sets the version string to what is stored in the Go debug info, with
	// the v prefix removed. (e.g. if the actual tag is formatted as v1.26.2 but
	// the GlobalSDKVersion would be 1.26.2).

	const unknown = "<unknown>"
	info, ok := debug.ReadBuildInfo()
	if !ok {
		// This can only happen if we somehow built without go modules, so
		// it's basically impossible.
		return unknown
	}
	for _, dep := range info.Deps {
		if dep.Path == "github.com/github/github-telemetry-go" {
			return strings.TrimPrefix(dep.Version, "v")
		}
	}
	// Somehow the code is run without being in the deps. This should be
	// impossible unless this is a fork.
	return unknown
}()
