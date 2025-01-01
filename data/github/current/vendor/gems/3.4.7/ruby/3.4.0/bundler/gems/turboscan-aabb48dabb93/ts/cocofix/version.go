package cocofix

import (
	_ "embed"
	"encoding/json"
)

//go:embed javascript/package-lock.json
var AIPackageLock string
var cachedAIVersion string

const packageName = "node_modules/@github/cocofix"

type lockedPackage struct {
	Version string `json:"version"`
}

type packageLock struct {
	Packages map[string]lockedPackage `json:"packages"`
}

func getAIVersion() string {
	if cachedAIVersion != "" {
		return cachedAIVersion
	}
	packageLock := packageLock{}
	err := json.Unmarshal([]byte(AIPackageLock), &packageLock)
	if err != nil {
		cachedAIVersion = "unknown"
		return cachedAIVersion
	}
	if cocofixPackage, ok := packageLock.Packages[packageName]; ok {
		cachedAIVersion = cocofixPackage.Version
	} else {
		cachedAIVersion = "unknown"
	}
	return cachedAIVersion
}
