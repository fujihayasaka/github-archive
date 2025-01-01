package models

import "time"

// EnterprisePolicy represents an enterprise-level license policy.
type EnterprisePolicy struct {
	ID                        uint64
	CreatedAt                 time.Time
	EnterpriseID              uint64
	Policy                    *Policy
	Hash                      []byte
	CustomRemediationGuidance string
}
