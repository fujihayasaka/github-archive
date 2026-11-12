// Package runnerlabels defines well-known runner label constants shared across
// the launcher and metrics layers.
package runnerlabels

const (
	// CustomImageLabel is the runner label for the custom VM image pool.
	CustomImageLabel = "ubuntu-cca-77785908-7ef3-498a-9ae0-bbebb95125d3"

	// MacOSLatestLabel is the runner label for the latest macOS runner.
	MacOSLatestLabel = "macos-latest"

	// SelfHostedLabel is the runner label for self-hosted runners.
	SelfHostedLabel = "self-hosted"

	// UbuntuLatestLabel is the default runner label used when no custom runner is specified.
	UbuntuLatestLabel = "ubuntu-latest"

	// WindowsLatestLabel is the runner label for the latest Windows runner.
	WindowsLatestLabel = "windows-latest"
)
