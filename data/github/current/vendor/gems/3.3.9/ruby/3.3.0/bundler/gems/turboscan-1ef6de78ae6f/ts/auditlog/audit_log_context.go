// Package auditlog contains logic and types for audit logging
package auditlog

type AuditLogContext struct {
	Actor      string `json:"actor,omitempty"`
	OrgID      uint64 `json:"org_id,omitempty"`
	Org        string `json:"org,omitempty"`
	BusinessID uint64 `json:"business_id,omitempty"`
	Business   string `json:"business,omitempty"`
}
