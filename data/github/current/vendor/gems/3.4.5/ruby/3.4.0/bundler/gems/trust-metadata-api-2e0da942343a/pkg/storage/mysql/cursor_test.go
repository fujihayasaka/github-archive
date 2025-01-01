package mysql

import (
	"fmt"
	"testing"

	"github.com/github/trust-metadata-api/pkg/attestation"
	"github.com/stretchr/testify/assert"
)

func TestCursor(t *testing.T) {
	// Test case: New cursor with default values
	cursor := &DescCursor{}
	err := cursor.Validate()
	assert.Nil(t, err)
	assert.Equal(t, int32(1), cursor.PerPage)

	// Test case: New cursor with valid PerPage
	cursor = &DescCursor{}
	cursor.PerPage = 50
	err = cursor.Validate()
	assert.Nil(t, err)
	assert.Equal(t, int32(50), cursor.PerPage)

	// Test case: New cursor with invalid PerPage
	cursor = &DescCursor{}
	cursor.PerPage = 200
	err = cursor.Validate()
	assert.Nil(t, err)
	assert.Equal(t, int32(100), cursor.PerPage)

	// Test case: New cursor with both Before and After set
	cursor = &DescCursor{}
	cursor.Before = 1
	cursor.After = 1
	err = cursor.Validate()
	assert.NotNil(t, err)

	// Test case: IsBefore method with Before set
	cursor = &DescCursor{}
	cursor.Before = 1
	assert.True(t, cursor.IsBefore())

	// Test case: IsBefore method with Before not set
	cursor = &DescCursor{}
	assert.False(t, cursor.IsBefore())

	// Test case: GetQueryLimit method with various PerPage
	cursor = &DescCursor{}
	cursor.PerPage = 50
	assert.Equal(t, int32(51), cursor.GetQueryLimit())
	cursor = &DescCursor{}
	cursor.PerPage = 0
	assert.Equal(t, int32(0), cursor.GetQueryLimit())

	// Test case: GetFetchDirection method with Before set
	cursor = &DescCursor{}
	cursor.Before = 1
	assert.Equal(t, "ASC", cursor.GetFetchDirection())

	// Test case: GetFetchDirection method with Before not set
	cursor = &DescCursor{}
	assert.Equal(t, "DESC", cursor.GetFetchDirection())

	// Test case: NewCursor with various input values
	cursor, err = NewCursor(50, 1, 0)
	assert.Nil(t, err)
	assert.Equal(t, int32(50), cursor.PerPage)
	assert.Equal(t, uint64(1), cursor.After)
	cursor, err = NewCursor(0, 0, 1)
	assert.Nil(t, err)
	assert.Equal(t, defaultCursorPerPage, cursor.PerPage)
	assert.Equal(t, uint64(1), cursor.Before)
	_, err = NewCursor(0, 1, 1)
	assert.NotNil(t, err)
}

func TestCalculatePageInfoWithCustomSort(t *testing.T) {
	attestations := make([]attestation.Record, 50)
	for i := range 50 {
		attestations[i] = attestation.Record{ID: uint64(50 - i)}
	}

	cursor := &AscCursor{}
	cursor.PerPage = 30
	cursor.Before = 25

	// pagedRecords, pageInfo, err := calculatePageInfoWithCustomSort(cursor, attestations[24:])
	// assert.NoError(t, err)
	// assert.Len(t, pagedRecords, 26)
	// assert.Equal(t, 26, int(pageInfo.StartCursor))
	// assert.Equal(t, 1, int(pageInfo.EndCursor))
	// assert.Equal(t, 26, int(pagedRecords[0].ID))

	pagedRecords, pageInfo, err := calculatePageInfo(cursor, attestations[24:])
	assert.NoError(t, err)
	assert.Len(t, pagedRecords, 26, fmt.Sprintf("pagedRecords: %v", pagedRecords))
	assert.Equal(t, 1, int(pageInfo.StartCursor))
	assert.Equal(t, 26, int(pageInfo.EndCursor))
	assert.Equal(t, 1, int(pagedRecords[0].ID))

	cursor.Before = 0
	cursor.After = 35
	pagedRecords, pageInfo, err = calculatePageInfo(cursor, attestations[:15])
	assert.NoError(t, err)
	assert.Len(t, pagedRecords, 15, fmt.Sprintf("pagedRecords: %v", pagedRecords))
	assert.Equal(t, 36, int(pageInfo.StartCursor))
	assert.Equal(t, 50, int(pageInfo.EndCursor))
	assert.Equal(t, 36, int(pagedRecords[0].ID), fmt.Sprintf("actual ID: %d", int(pagedRecords[0].ID)))
}
