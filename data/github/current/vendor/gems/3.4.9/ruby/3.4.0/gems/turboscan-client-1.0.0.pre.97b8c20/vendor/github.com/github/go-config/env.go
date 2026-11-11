package config

import (
	"os"
	"strings"
)

// GetEnv uses the provided application metadata to provide the correct precedence ordered configuration
// value from the Environment using based on the supplied key.
// The precedence ordering is:
// Site i.e. AM4_AMS_FOO
// Region i.e. AMS_FOO
// Default i.e. FOO
// No distinction is made between the key being absent and it being set to an empty string.
func GetEnv(meta *Metadata, key string) string {
	return getEnv(os.Getenv, meta, key)
}

// ScreamingSnakeCase converts the given string to SCREAMING_SNAKE_CASE as used by most Environment
// variables.
func ScreamingSnakeCase(s string) string {
	return strings.ToUpper(strings.ReplaceAll(s, "-", "_"))
}

// This is separated to support testing without manipulating the actual ENV.
func getEnv(getenv func(string) string, meta *Metadata, key string) string {

	if v := getenv(ScreamingSnakeCase(meta.Site) + "_" + key); v != "" {
		return v
	}
	if v := getenv(ScreamingSnakeCase(meta.Region) + "_" + key); v != "" {
		return v
	}
	if v := getenv(key); v != "" {
		return v
	}
	return ""
}
