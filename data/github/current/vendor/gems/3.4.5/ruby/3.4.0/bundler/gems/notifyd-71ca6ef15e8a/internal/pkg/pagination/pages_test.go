package pagination

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewStandardPages(t *testing.T) {
	cursor := "test"
	pages := NewStandardPages(cursor)
	assert.Equal(t, cursor, pages.NextCursor())
}

func TestStandardPages_ReturnCursor(t *testing.T) {
	pages := NewStandardPages("6")
	assert.True(t, pages.ReturnNextCursor())
}

func TestNewEmptyStandardPages(t *testing.T) {
	pages := NewEmptyStandardPages()
	assert.Equal(t, "", pages.NextCursor())
}

func TestEmptyStandardPages_ReturnCursor(t *testing.T) {
	pages := NewEmptyStandardPages()
	assert.False(t, pages.ReturnNextCursor())
}
