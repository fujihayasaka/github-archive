package dependencies

import (
	dg "github.com/github/dependency-graph-api/gen/go/v1"
	"github.com/github/osslicensecompliance/internal/models"
)

// DGPackageManagerToModel converts a dependency graph package manager to a models package
func DGPackageManagerToModel(dgPM dg.PackageManager) models.PackageManager {
	switch dgPM {
	case dg.PackageManager_PACKAGE_MANAGER_NPM:
		return models.PMnpm
	case dg.PackageManager_PACKAGE_MANAGER_PIP:
		return models.PMpip
	case dg.PackageManager_PACKAGE_MANAGER_MAVEN:
		return models.PMmaven
	case dg.PackageManager_PACKAGE_MANAGER_NUGET:
		return models.PMnuget
	case dg.PackageManager_PACKAGE_MANAGER_COMPOSER:
		return models.PMcomposer
	case dg.PackageManager_PACKAGE_MANAGER_GOMOD:
		return models.PMgomod
	case dg.PackageManager_PACKAGE_MANAGER_RUST:
		return models.PMrust
	case dg.PackageManager_PACKAGE_MANAGER_ACTIONS:
		return models.PMactions
	case dg.PackageManager_PACKAGE_MANAGER_PUB:
		return models.PMpub
	case dg.PackageManager_PACKAGE_MANAGER_SWIFT:
		return models.PMswift
	case dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS:
		return models.PMrubygems
	default:
		return models.PMunknown
	}
}

// ModelPackageManagerToDG converts a models package manager to a dependency graph package manager
func ModelPackageManagerToDG(pm models.PackageManager) dg.PackageManager {
	switch pm {
	case models.PMnpm:
		return dg.PackageManager_PACKAGE_MANAGER_NPM
	case models.PMpip:
		return dg.PackageManager_PACKAGE_MANAGER_PIP
	case models.PMmaven:
		return dg.PackageManager_PACKAGE_MANAGER_MAVEN
	case models.PMnuget:
		return dg.PackageManager_PACKAGE_MANAGER_NUGET
	case models.PMcomposer:
		return dg.PackageManager_PACKAGE_MANAGER_COMPOSER
	case models.PMgomod:
		return dg.PackageManager_PACKAGE_MANAGER_GOMOD
	case models.PMrust:
		return dg.PackageManager_PACKAGE_MANAGER_RUST
	case models.PMactions:
		return dg.PackageManager_PACKAGE_MANAGER_ACTIONS
	case models.PMpub:
		return dg.PackageManager_PACKAGE_MANAGER_PUB
	case models.PMswift:
		return dg.PackageManager_PACKAGE_MANAGER_SWIFT
	case models.PMrubygems:
		return dg.PackageManager_PACKAGE_MANAGER_RUBYGEMS
	default:
		return dg.PackageManager_PACKAGE_MANAGER_UNKNOWN
	}
}
