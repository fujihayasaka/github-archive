package oteltwirp

// Version is the current release version
func Version() string {
	return "v0.2.0"
}

// SemVersion is the semantic version supplied to the trace provider
func SemVersion() string {
	return "semver:" + Version()
}
