// Package o11y (observability)provides utility methods for observability.
//
// We should intentionally not build too many abstractions on top of
// github-telemetry-go, and instead try to upstream larger changes.
// Nevertheless, there are things that are specific to this project or that
// might be more controversial. Rather than spreading those utilities around
// the codebase we aim to put them all here.
package o11y
