package auditlog_test

import (
	"testing"

	"github.com/github/turboscan/ts/auditlog"
	"github.com/stretchr/testify/assert"
)

func TestScan(t *testing.T) {
	var auditLogContext auditlog.AuditLogContext
	err := auditLogContext.Scan([]byte("{}"))
	assert.NoError(t, err)
	assert.Equal(t, auditlog.AuditLogContext{}, auditLogContext)

	err = auditLogContext.Scan([]byte("{\"org_id\": 10}"))
	assert.NoError(t, err)
	assert.Equal(t, auditlog.AuditLogContext{OrgID: 10}, auditLogContext)
}

func TestValue(t *testing.T) {
	auditLogContext := auditlog.AuditLogContext{}
	value, err := auditLogContext.Value()
	assert.NoError(t, err)
	assert.Equal(t, "{}", value)

	auditLogContext.OrgID = 10
	value, err = auditLogContext.Value()
	assert.NoError(t, err)
	assert.Equal(t, "{\"org_id\":10}", value)
}
