package streaming

import (
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestNewBlobFilter(t *testing.T) {
	examples := []struct {
		label          string
		filters        []BlobFilterOpt
		expectedResult *BlobFilter
	}{
		{
			label:          "no filters",
			filters:        []BlobFilterOpt{},
			expectedResult: nil,
		},
		{
			label:          "truncate",
			filters:        []BlobFilterOpt{WithTruncation(9876)},
			expectedResult: &BlobFilter{TruncateAt: 9876},
		},
		{
			label:          "max_size",
			filters:        []BlobFilterOpt{WithMaxSize(1024)},
			expectedResult: &BlobFilter{MaxSize: 1024},
		},
		{
			label:          "min_size",
			filters:        []BlobFilterOpt{WithMinSize(5)},
			expectedResult: &BlobFilter{MinSize: 5},
		},
		{
			label:          "plain_text_only",
			filters:        []BlobFilterOpt{WithPlainTextOnly()},
			expectedResult: &BlobFilter{PlainTextOnly: true},
		},
		{
			label:          "utf8_only",
			filters:        []BlobFilterOpt{WithUTF8Only()},
			expectedResult: &BlobFilter{Utf8Only: true},
		},
		{
			label:          "max_line_length",
			filters:        []BlobFilterOpt{WithMaxLineLength(100)},
			expectedResult: &BlobFilter{MaxLineLength: 100},
		},
	}

	for _, ex := range examples {
		t.Run(ex.label, func(t *testing.T) {
			req := NewBatchBlobsRequest(nil, nil, nil, ex.filters...)
			assert.Equal(t, ex.expectedResult, req.Filters)
		})
	}
}
