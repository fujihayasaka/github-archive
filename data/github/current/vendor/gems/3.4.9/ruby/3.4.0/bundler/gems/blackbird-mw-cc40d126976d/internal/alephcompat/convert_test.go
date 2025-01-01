package alephcompat

import (
	"testing"

	pb "github.com/github/blackbird-mw/internal/proto/query/v1"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// These test cases have been ported from the Aleph source.

// Two documents are used for these test cases to help simulate
// when Blackbird returns multiple documents for a single query.
var (
	doc1 = []byte(`function bar() {
  haz()
}

function haz() {}

function other() {
    bar()
}`)

	doc1BarIdentStartOffset = uint32(9)
	doc1BarIdentEndOffset   = uint32(12)

	doc1BarExtentStartOffset = uint32(0)
	doc1BarExtentEndOffset   = uint32(26)

	doc1HazReferenceIdentStartOffset = uint32(19)
	doc1HazReferenceIdentEndOffset   = uint32(22)

	doc1HazIdentStartOffset = uint32(37)
	doc1HazIdentEndOffset   = uint32(40)

	doc1HazExtentStartOffset = uint32(28)
	doc1HazExtentEndOffset   = uint32(45)

	doc2 = []byte(`function haz() {
  bar()
}

function bar() {}`)

	doc2HazIdentStartOffset = uint32(9)
	doc2HazIdentEndOffset   = uint32(12)

	doc2HazExtentStartOffset = uint32(0)
	doc2HazExtentEndOffset   = uint32(26)

	doc2BarReferenceIdentStartOffset = uint32(19)
	doc2BarReferenceIdentEndOffset   = uint32(22)

	doc2BarIdentStartOffset = uint32(37)
	doc2BarIdentEndOffset   = uint32(40)

	doc2BarExtentStartOffset = uint32(28)
	doc2BarExtentEndOffset   = uint32(45)
)

func TestByteOffsetsForTestData(t *testing.T) {
	// Ensure doc1 byte offsets are valid.
	require.Equal(t, "bar", string(doc1[doc1BarIdentStartOffset:doc1BarIdentEndOffset]))
	require.Equal(t, "haz", string(doc1[doc1HazReferenceIdentStartOffset:doc1HazReferenceIdentEndOffset]))
	require.Equal(t, "haz", string(doc1[doc1HazIdentStartOffset:doc1HazIdentEndOffset]))

	// Ensure doc2 byte offsets are valid.
	require.Equal(t, "haz", string(doc2[doc2HazIdentStartOffset:doc2HazIdentEndOffset]))
	require.Equal(t, "bar", string(doc2[doc2BarReferenceIdentStartOffset:doc2BarReferenceIdentEndOffset]))
	require.Equal(t, "bar", string(doc2[doc2BarIdentStartOffset:doc2BarIdentEndOffset]))
}

func TestExtentRangeFromOffsets(t *testing.T) {
	// doc1

	// Validate extent range for "bar" function definition.
	require.Equal(t, "function bar() {\n  haz()\n}", string(doc1[doc1BarExtentStartOffset:doc1BarExtentEndOffset]))

	doc1BarExtent := ExtentRangeFromOffsets(doc1, doc1BarExtentStartOffset, doc1BarExtentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      0,
				Character: 0,
			},
			End: &pb.AlephPosition{
				Line:      2,
				Character: 1,
			},
		},
		doc1BarExtent,
	)

	// Validate extent range for "haz" function definition.
	require.Equal(t, "function haz() {}", string(doc1[doc1HazExtentStartOffset:doc1HazExtentEndOffset]))

	doc1HazExtent := ExtentRangeFromOffsets(doc1, doc1HazExtentStartOffset, doc1HazExtentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      4,
				Character: 0,
			},
			End: &pb.AlephPosition{
				Line:      4,
				Character: 17,
			},
		},
		doc1HazExtent,
	)

	// doc2

	// Validate extent range for "haz" function definition.
	require.Equal(t, "function haz() {\n  bar()\n}", string(doc2[doc2HazExtentStartOffset:doc2HazExtentEndOffset]))

	doc2HazExtent := ExtentRangeFromOffsets(doc2, doc2HazExtentStartOffset, doc2HazExtentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      0,
				Character: 0,
			},
			End: &pb.AlephPosition{
				Line:      2,
				Character: 1,
			},
		},
		doc2HazExtent,
	)

	// Validate extent range for "bar" function definition.
	require.Equal(t, "function bar() {}", string(doc2[doc2BarExtentStartOffset:doc2BarExtentEndOffset]))

	doc2BarExtent := ExtentRangeFromOffsets(doc2, doc2BarExtentStartOffset, doc2BarExtentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      4,
				Character: 0,
			},
			End: &pb.AlephPosition{
				Line:      4,
				Character: 17,
			},
		},
		doc2BarExtent,
	)

}

func TestIdentLineFromOffsets(t *testing.T) {
	// doc1

	// Validate symbol line for "bar" function definition.
	require.Equal(t, "function bar() {", IdentLineFromOffsets(doc1, doc1BarIdentStartOffset, doc1BarIdentEndOffset))

	// Validate symbol line for "haz" reference.
	require.Equal(t, "  haz()", IdentLineFromOffsets(doc1, doc1HazReferenceIdentStartOffset, doc1HazReferenceIdentEndOffset))

	// Validate symbol line for "haz" function definition when no trailing newline.
	require.Equal(t, "function haz() {}", IdentLineFromOffsets(doc1, doc1HazIdentStartOffset, doc1HazIdentEndOffset))

	// doc2

	// Validate symbol line for "haz" function definition.
	require.Equal(t, "function haz() {", IdentLineFromOffsets(doc2, doc2HazIdentStartOffset, doc2HazIdentEndOffset))

	// Validate symbol line for "bar" reference.
	require.Equal(t, "  bar()", IdentLineFromOffsets(doc2, doc2BarReferenceIdentStartOffset, doc2BarReferenceIdentEndOffset))

	// Validate symbol line for "bar" function definition when no trailing newline.
	require.Equal(t, "function bar() {}", IdentLineFromOffsets(doc2, doc2BarIdentStartOffset, doc2BarIdentEndOffset))
}

func TestIdentRangeFromOffsets(t *testing.T) {
	// doc1

	// Validate ident range for "bar" function definition.
	doc1BarIdent := IdentRangeFromOffsets(doc1, doc1BarIdentStartOffset, doc1BarIdentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      0,
				Character: 9,
			},
			End: &pb.AlephPosition{
				Line:      0,
				Character: 12,
			},
		},
		doc1BarIdent,
	)

	// Validate ident range for "haz" reference.
	doc1HazReferenceIdent := IdentRangeFromOffsets(doc1, doc1HazReferenceIdentStartOffset, doc1HazReferenceIdentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      1,
				Character: 2,
			},
			End: &pb.AlephPosition{
				Line:      1,
				Character: 5,
			},
		},
		doc1HazReferenceIdent,
	)

	// Validate ident range for "haz" function definition.
	doc1HazIdent := IdentRangeFromOffsets(doc1, doc1HazIdentStartOffset, doc1HazIdentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      4,
				Character: 9,
			},
			End: &pb.AlephPosition{
				Line:      4,
				Character: 12,
			},
		},
		doc1HazIdent,
	)

	// doc2

	// Validate ident range for "haz" function definition.
	doc2HazIdent := IdentRangeFromOffsets(doc2, doc2HazIdentStartOffset, doc2HazIdentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      0,
				Character: 9,
			},
			End: &pb.AlephPosition{
				Line:      0,
				Character: 12,
			},
		},
		doc2HazIdent,
	)

	// Validate ident range for "bar" reference.
	doc2BarReferenceIdent := IdentRangeFromOffsets(doc2, doc2BarReferenceIdentStartOffset, doc2BarReferenceIdentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      1,
				Character: 2,
			},
			End: &pb.AlephPosition{
				Line:      1,
				Character: 5,
			},
		},
		doc2BarReferenceIdent,
	)

	// Validate ident range for "bar" function definition.
	doc2BarIdent := IdentRangeFromOffsets(doc2, doc2BarIdentStartOffset, doc2BarIdentEndOffset)
	assert.Equal(t,
		&pb.AlephRange{
			Start: &pb.AlephPosition{
				Line:      4,
				Character: 9,
			},
			End: &pb.AlephPosition{
				Line:      4,
				Character: 12,
			},
		},
		doc2BarIdent,
	)
}
