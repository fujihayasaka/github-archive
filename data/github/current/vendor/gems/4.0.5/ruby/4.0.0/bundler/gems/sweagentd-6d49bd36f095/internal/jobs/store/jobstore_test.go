package store

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestBuildCosmosCondition(t *testing.T) {
	t.Run("empty conditions", func(t *testing.T) {
		assert.Equal(t, "", BuildCosmosCondition(nil))
		assert.Equal(t, "", BuildCosmosCondition([]FieldCondition{}))
	})

	t.Run("single value equality", func(t *testing.T) {
		cond := []FieldCondition{{Path: "pull_request_id", Value: int64(0)}}
		assert.Equal(t, "FROM c WHERE c.pull_request_id = 0", BuildCosmosCondition(cond))
	})

	t.Run("single string value equality", func(t *testing.T) {
		cond := []FieldCondition{{Path: "status", Value: "pending"}}
		assert.Equal(t, "FROM c WHERE c.status = 'pending'", BuildCosmosCondition(cond))
	})

	t.Run("multiple conditions with AND", func(t *testing.T) {
		cond := []FieldCondition{
			{Path: "pull_request_id", Value: int64(0)},
			{Path: "status", Value: "pending"},
		}
		assert.Equal(t, "FROM c WHERE c.pull_request_id = 0 AND c.status = 'pending'", BuildCosmosCondition(cond))
	})

	t.Run("values generates IN clause", func(t *testing.T) {
		cond := []FieldCondition{{Path: "pull_request_id", Values: []any{int64(0), int64(123)}}}
		assert.Equal(t, "FROM c WHERE c.pull_request_id IN (0, 123)", BuildCosmosCondition(cond))
	})

	t.Run("values with strings generates IN clause", func(t *testing.T) {
		cond := []FieldCondition{{Path: "status", Values: []any{"pending", "running"}}}
		assert.Equal(t, "FROM c WHERE c.status IN ('pending', 'running')", BuildCosmosCondition(cond))
	})

	t.Run("values takes precedence over value", func(t *testing.T) {
		cond := []FieldCondition{{Path: "pull_request_id", Value: int64(99), Values: []any{int64(0), int64(123)}}}
		assert.Equal(t, "FROM c WHERE c.pull_request_id IN (0, 123)", BuildCosmosCondition(cond))
	})
}
