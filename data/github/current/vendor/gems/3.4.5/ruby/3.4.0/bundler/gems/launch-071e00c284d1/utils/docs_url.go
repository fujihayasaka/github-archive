package utils

import (
	"fmt"
	"strings"
)

const (
	GitHubDocsBaseURL          = "https://docs.github.com"
	DotcomBusinessDocsBasePath = "/enterprise-cloud@latest"
	GHESDocsBasePath           = "/enterprise-server@"
)

func GetDotcomDocsURL(path string) string {
	return fmt.Sprintf("%s%s", GitHubDocsBaseURL, path)
}

func GetGHECDocsURL(path string) string {
	return fmt.Sprintf("%s%s%s", GitHubDocsBaseURL, DotcomBusinessDocsBasePath, path)
}

func GetGHESDocsURL(path string, version string) string {

	// In case version is 3.4.0, then we need only 3.4 for docs
	// Fallback to `latest`, if version is not passed
	versionParts := strings.Split(version, ".")
	if len(versionParts) > 2 {
		version = fmt.Sprintf("%s.%s", versionParts[0], versionParts[1])
	} else if len(versionParts) < 2 {
		version = "latest"
	}

	return fmt.Sprintf("%s%s%s%s", GitHubDocsBaseURL, GHESDocsBasePath, version, path)
}
