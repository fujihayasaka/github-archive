package models

// PackageManager is the name of package manager.
// These values align with the package managers available in dependency graph.
// int32 is used to match the proto and not have to cast the values.
type PackageManager int32

func (pm PackageManager) String() string {
	switch pm {
	case PMunknown:
		return "unknown"
	case PMrubygems:
		return "rubygems"
	case PMnpm:
		return "npm"
	case PMpip:
		return "pip"
	case PMmaven:
		return "maven"
	case PMnuget:
		return "nuget"
	case PMcomposer:
		return "composer"
	case PMgomod:
		return "gomod"
	case PMrust:
		return "rust"
	case PMactions:
		return "actions"
	case PMpub:
		return "pub"
	case PMswift:
		return "swift"
	default:
		return "unknown"
	}
}

// Enum values aligned with Dependency Graph. See:
// https://github.com/github/dependency-graph-api/blob/master/proto/twirp/v1/dependency_graph_api.proto#L108
const (
	PMunknown  PackageManager = 0
	PMrubygems PackageManager = 1
	PMnpm      PackageManager = 2
	PMpip      PackageManager = 3
	PMmaven    PackageManager = 4
	PMnuget    PackageManager = 5
	PMcomposer PackageManager = 6
	PMgomod    PackageManager = 7
	PMrust     PackageManager = 8
	PMactions  PackageManager = 9
	PMpub      PackageManager = 10
	PMswift    PackageManager = 11
)

// Version is generally going to be a semver version, but can be any string.
type Version string

// Package represents a single package which is a dependency for a
// repository or artifact.
type Package struct {
	PackageManager PackageManager
	Name           string
	Version        Version

	// DevDependency is true if the package is known to be in a development
	// scope.
	DevDependency bool

	// License is the SPDX license identifier for the package.
	License string

	// Version where license was taken from
	// When no exact version was specified or no license existed for versions
	LicenseVersion Version

	// CalculatedLicense indicates that license was calculated
	// An inexact version was specified in the manifest or no license was available for the version specified.
	// The license field contains the most recent license available.
	CalculatedLicense bool

	// Manifests is where the package was found in the repository.
	Manifests []string
}
