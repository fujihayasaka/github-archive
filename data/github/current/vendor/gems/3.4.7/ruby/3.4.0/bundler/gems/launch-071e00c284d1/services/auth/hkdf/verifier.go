package hkdf

import (
	"crypto/subtle"
	"math"
	"time"
)

type Verifier interface {
	Verify(workflowID string, timestamp time.Time, message, signature []byte) (bool, error)
}

type verifier struct {
	validitySeconds float64
	keyGenerators   []KeyGenerator
}

type nullVerifier struct {
}

func (v *nullVerifier) Verify(_ string, _ time.Time, _, _ []byte) (bool, error) {
	return true, nil
}

// NewNullVerifier returns a Verifier than always returns true
func NewNullVerifier() Verifier {
	return &nullVerifier{}
}

func NewVerifier(keyGenerators []KeyGenerator, validity time.Duration) Verifier {
	return &verifier{
		keyGenerators:   keyGenerators,
		validitySeconds: validity.Seconds(),
	}
}

func (v *verifier) Verify(workflowID string, timestamp time.Time, message, signature []byte) (bool, error) {
	if !v.isValidTimestamp(timestamp) {
		return false, nil
	}

	for _, keyGenerator := range v.keyGenerators {
		signed, err := GenerateAndSign(keyGenerator, workflowID, timestamp, message)
		if err != nil {
			return false, err
		}
		if subtle.ConstantTimeCompare(signature, signed) == 1 {
			return true, nil
		}
	}

	return false, nil
}

func (v *verifier) isValidTimestamp(timestamp time.Time) bool {
	since := time.Since(timestamp)
	return math.Abs(since.Seconds()) <= v.validitySeconds
}
