// Package auditlog contains logic and types for audit logging
package auditlog

import (
	"database/sql/driver"
	"encoding/json"

	"github.com/pkg/errors"
)

type AuditLogContext struct {
	// Note: This is persisted in the database as a JSON field; currently it is not safe to remove a field.
	// If you really need to remove a field, update the unmarshaling code in `Scan` to be able to handle unknown fields.
	Actor      string `json:"actor,omitempty"`
	OrgID      uint64 `json:"org_id,omitempty"`
	Org        string `json:"org,omitempty"`
	BusinessID uint64 `json:"business_id,omitempty"`
	Business   string `json:"business,omitempty"`
}

func (auditLogContext *AuditLogContext) Scan(value interface{}) error {
	if value == nil {
		return nil
	}

	bytes, ok := value.([]byte)
	if !ok {
		return errors.New("audit log context was not bytes")
	}

	result := AuditLogContext{}
	err := json.Unmarshal(bytes, &result)
	*auditLogContext = result
	return err
}

func (auditLogContext *AuditLogContext) Value() (driver.Value, error) {
	if auditLogContext == nil {
		return nil, nil
	}

	bytes, err := json.Marshal(auditLogContext)
	if err != nil {
		return nil, errors.Wrap(err, "failed to marshal audit log context")
	}

	// We serialize the JSON as UTF-8 because MySQL doesn't like creating JSON fields directly from binary data.
	return string(bytes), nil
}
