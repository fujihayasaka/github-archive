package models

import "github.com/github/osslicensecompliance/pkg/proto/v0"

// Version is generally going to be a semver version, but can be any string.
type Version string

// Package represents a single package which is a dependency for a
// repository or artifact.
type Package struct {
	PackageManager proto.PackageManager
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

	// PackageRepoNWO is the repository name-with-owner of the package source.
	PackageRepoNWO string
}
