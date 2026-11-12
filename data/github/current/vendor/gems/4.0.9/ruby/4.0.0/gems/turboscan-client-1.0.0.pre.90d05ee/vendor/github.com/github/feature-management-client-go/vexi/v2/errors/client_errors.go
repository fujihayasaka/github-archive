package errors

import "errors"

// ErrFeatureFlagNameRequired is returned when the feature flag name is not provided in the IsEnabled call.
var ErrFeatureFlagNameRequired = errors.New("feature flag name required")

// ErrFeatureFlagNotFound should be returned by adapters when the requested feature flag is not found.
var ErrFeatureFlagNotFound = errors.New("feature flag not found")

// ErrSegmentNotFound should be returned by adapters when the requested segment is not found.
var ErrSegmentNotFound = errors.New("segment not found")
