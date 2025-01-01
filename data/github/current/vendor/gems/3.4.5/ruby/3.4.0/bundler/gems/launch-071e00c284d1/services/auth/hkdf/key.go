package hkdf

import "time"

type DerivedKey struct {
	// Key used for signing, but not included in signed requests
	Key []byte `json:"key"`
	// Built into `Key`, included in signed requests for isolation
	WorkflowID string `json:"workflowID"`
	// Built into `Key`, included in signed requests for expiration
	Timestamp time.Time `json:"ts"`
}
