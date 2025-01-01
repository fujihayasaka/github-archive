package aqueduct

import (
	"context"
	"time"
)

// Job contains the base fields for an Aqueduct job.
type Job struct {
	App       string
	Queue     string
	ID        string
	Payload   []byte
	Headers   map[string]string
	DeliverAt time.Time
}

// JobHandler is a func type used by a Worker for handling a received job.
type JobHandler func(context.Context, ReceiveResult) error

// JobErrorPolicy represents the policy to control what followup action should
// be taken when a JobHandler returns an error.
type JobErrorPolicy int

const (
	// IgnoreJobErr requires that a job should be allowed to timeout on error.
	// If eligible the job may be redelivered.
	IgnoreJobErr JobErrorPolicy = iota

	// AckJobErr requires that a job should be ack'd as successful on error.
	AckJobErr

	// NackJobErr requires that a job should be ack'd as failed on error. The
	// job will not be redelivered.
	NackJobErr
)

// InvalidPayloadPolicy determines how a worker reacts to invalid payload HMAC
// signatures.
type InvalidPayloadPolicy int

const (
	// InvalidPayloadPolicyReject will throw away jobs with invalid HMAC
	// signatures by immediately ACK-ing without calling the handler.
	// Rejecting invalid payloads is the default behavior.
	InvalidPayloadPolicyReject InvalidPayloadPolicy = iota

	// InvalidPayloadPolicyIgnore will ignore invalid HMAC signatures and call
	// the handler as normal.
	InvalidPayloadPolicyIgnore
)
