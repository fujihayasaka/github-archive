package dependencies

import (
	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/osslicensecompliance/pkg/proto/v0"
)

// DGPackageManagerToModel converts a dependency graph package manager to a models package.
// These should actually be the same values, but this ensures that if they diverge we
// handle it here.
func DGPackageManagerToModel(dgPM dg.PackageManager) proto.PackageManager {
	switch dgPM {
	case dg.PackageManager_PACKAGE_MANAGER_NPM:
		return proto.PackageManager_PACKAGE_MANAGER_NPM
	case dg.PackageManager_PACKAGE_MANAGER_PIP:
		return proto.PackageManager_PACKAGE_MANAGER_PIP
	case dg.PackageManager_PACKAGE_MANAGER_MAVEN:
		return proto.PackageManager_PACKAGE_MANAGER_MAVEN
	case dg.PackageManager_PACKAGE_MANAGER_NUGET:
		return proto.PackageManager_PACKAGE_MANAGER_NUGET
	case dg.PackageManager_PACKAGE_MANAGER_COMPOSER:
		return proto.PackageManager_PACKAGE_MANAGER_COMPOSER
	case dg.PackageManager_PACKAGE_MANAGER_GOMOD:
		return proto.PackageManager_PACKAGE_MANAGER_GOMOD
	case dg.PackageManager_PACKAGE_MANAGER_RUST:
		return proto.PackageManager_PACKAGE_MANAGER_RUST
	case dg.PackageManager_PACKAGE_MANAGER_ACTIONS:
		return proto.PackageManager_PACKAGE_MANAGER_ACTIONS
	case dg.PackageManager_PACKAGE_MANAGER_PUB:
		return proto.PackageManager_PACKAGE_MANAGER_PUB
	case dg.PackageManager_PACKAGE_MANAGER_SWIFT:
		return proto.PackageManager_PACKAGE_MANAGER_SWIFT
	case dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS:
		return proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS
	default:
		return proto.PackageManager_PACKAGE_MANAGER_UNKNOWN
	}
}

// ModelPackageManagerToDG converts a models package manager to a dependency graph package manager
func ModelPackageManagerToDG(pm proto.PackageManager) dg.PackageManager {
	switch pm {
	case proto.PackageManager_PACKAGE_MANAGER_NPM:
		return dg.PackageManager_PACKAGE_MANAGER_NPM
	case proto.PackageManager_PACKAGE_MANAGER_PIP:
		return dg.PackageManager_PACKAGE_MANAGER_PIP
	case proto.PackageManager_PACKAGE_MANAGER_MAVEN:
		return dg.PackageManager_PACKAGE_MANAGER_MAVEN
	case proto.PackageManager_PACKAGE_MANAGER_NUGET:
		return dg.PackageManager_PACKAGE_MANAGER_NUGET
	case proto.PackageManager_PACKAGE_MANAGER_COMPOSER:
		return dg.PackageManager_PACKAGE_MANAGER_COMPOSER
	case proto.PackageManager_PACKAGE_MANAGER_GOMOD:
		return dg.PackageManager_PACKAGE_MANAGER_GOMOD
	case proto.PackageManager_PACKAGE_MANAGER_RUST:
		return dg.PackageManager_PACKAGE_MANAGER_RUST
	case proto.PackageManager_PACKAGE_MANAGER_ACTIONS:
		return dg.PackageManager_PACKAGE_MANAGER_ACTIONS
	case proto.PackageManager_PACKAGE_MANAGER_PUB:
		return dg.PackageManager_PACKAGE_MANAGER_PUB
	case proto.PackageManager_PACKAGE_MANAGER_SWIFT:
		return dg.PackageManager_PACKAGE_MANAGER_SWIFT
	case proto.PackageManager_PACKAGE_MANAGER_RUBYGEMS:
		return dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS
	default:
		return dg.PackageManager_PACKAGE_MANAGER_UNKNOWN
	}
}
