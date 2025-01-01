package pagination

import (
	"encoding/base64"
	"testing"

	"github.com/stretchr/testify/assert"
)

func TestCursorEncoding(t *testing.T) {
	original := "6"
	encoded := EncodeV1Cursor(original)
	decoded := DecodeCursor(encoded)
	assert.Equal(t, original, decoded)
}

func TestDecodingInvalidString(t *testing.T) {
	tcs := []struct {
		name    string
		encoded string
	}{
		{
			"Invalid base64 encoding",
			"???",
		},
		{
			"Invalid JSON format",
			base64.StdEncoding.EncodeToString([]byte("???")),
		},
		{
			"Invalid JSON content",
			base64.StdEncoding.EncodeToString([]byte(`{"unexpected": "value"}`)),
		},
		{
			"Invalid JSON types",
			base64.StdEncoding.EncodeToString([]byte(`{"v": "1", "ID": 1}`)),
		},
		{
			"Different cursor version",
			base64.StdEncoding.EncodeToString([]byte(`{"v": 1000, "ID": "1"}`)),
		},
	}

	for _, tc := range tcs {
		t.Run(tc.name, func(t *testing.T) {
			assert.Equal(t, "", DecodeCursor(tc.encoded))
		})
	}
}
