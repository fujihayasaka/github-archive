package mysqldb

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestPlaceholders(t *testing.T) {
	assert.Equal(t, "", Placeholders(-1))
	assert.Equal(t, "", Placeholders(0))
	assert.Equal(t, "?", Placeholders(1))
	assert.Equal(t, "?,?", Placeholders(2))
	assert.Equal(t, "?,?,?,?,?", Placeholders(5))
}
