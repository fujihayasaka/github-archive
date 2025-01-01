// Package pagination implements cursor-based pagination.
package pagination

import (
	"encoding/base64"
	"encoding/json"
)

// V1Cursor represents a V1 cursor.
type V1Cursor struct {
	V  int    `json:"v"`
	ID string `json:"id"`
}

// EncodeV1Cursor creates and encodes a cursor
func EncodeV1Cursor(cursor string) string {
	b, err := json.Marshal(V1Cursor{V: 1, ID: cursor})
	if err != nil {
		return ""
	}
	return base64.StdEncoding.EncodeToString(b)
}

// DecodeCursor decodes a cursor string
func DecodeCursor(cursor string) string {
	dec, _ := base64.StdEncoding.DecodeString(cursor)

	// Currently only V1 is supported so V1 encoding is expected.
	var v1 V1Cursor
	if err := json.Unmarshal(dec, &v1); err != nil {
		return ""
	}
	if v1.V != 1 {
		return ""
	}
	return v1.ID
}
