package mysql

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCursor(t *testing.T) {
	// Test case: New cursor with default values
	cursor := &Cursor{}
	err := cursor.Validate()
	assert.Nil(t, err)
	assert.Equal(t, int32(1), cursor.PerPage)

	// Test case: New cursor with valid PerPage
	cursor = &Cursor{PerPage: 50}
	err = cursor.Validate()
	assert.Nil(t, err)
	assert.Equal(t, int32(50), cursor.PerPage)

	// Test case: New cursor with invalid PerPage
	cursor = &Cursor{PerPage: 200}
	err = cursor.Validate()
	assert.Nil(t, err)
	assert.Equal(t, int32(100), cursor.PerPage)

	// Test case: New cursor with both Before and After set
	cursor = &Cursor{Before: 1, After: 1}
	err = cursor.Validate()
	assert.NotNil(t, err)

	// Test case: IsBefore method with Before set
	cursor = &Cursor{Before: 1}
	assert.True(t, cursor.IsBefore())

	// Test case: IsBefore method with Before not set
	cursor = &Cursor{}
	assert.False(t, cursor.IsBefore())

	// Test case: GetQueryLimit method with various PerPage
	cursor = &Cursor{PerPage: 50}
	assert.Equal(t, int32(51), cursor.GetQueryLimit())
	cursor = &Cursor{PerPage: 0}
	assert.Equal(t, int32(0), cursor.GetQueryLimit())

	// Test case: GetFetchDirection method with Before set
	cursor = &Cursor{Before: 1}
	assert.Equal(t, "ASC", cursor.GetFetchDirection())

	// Test case: GetFetchDirection method with Before not set
	cursor = &Cursor{}
	assert.Equal(t, "DESC", cursor.GetFetchDirection())

	// Test case: NewCursorFromRequest with various input values
	cursor, err = NewCursorFromRequest(50, 1, 0)
	assert.Nil(t, err)
	assert.Equal(t, int32(50), cursor.PerPage)
	assert.Equal(t, uint64(1), cursor.After)
	cursor, err = NewCursorFromRequest(0, 0, 1)
	assert.Nil(t, err)
	assert.Equal(t, defaultCursorPerPage, cursor.PerPage)
	assert.Equal(t, uint64(1), cursor.Before)
	_, err = NewCursorFromRequest(0, 1, 1)
	assert.NotNil(t, err)
}
