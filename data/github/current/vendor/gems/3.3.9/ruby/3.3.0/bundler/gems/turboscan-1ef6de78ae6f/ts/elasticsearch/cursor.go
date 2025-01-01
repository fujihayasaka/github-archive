package elasticsearch

import (
	"bytes"
	"encoding/base64"
	"encoding/json"
	"strings"

	"github.com/github/turboscan/ts"
	"github.com/pkg/errors"
)

type Cursor struct {
	AlertID   *uint64 `json:"alert_id,omitempty"`
	Weight    *uint16 `json:"weight,omitempty"`
	UpdatedAt *int64  `json:"updated_at,omitempty"`
	CreatedAt *int64  `json:"created_at,omitempty"`
}

func EncodeCursor(cursor Cursor) (string, error) {
	var buf bytes.Buffer
	encoder := base64.NewEncoder(base64.StdEncoding, &buf)
	err := json.NewEncoder(encoder).Encode(cursor)
	if err != nil {
		return "", err
	}
	err = encoder.Close()
	if err != nil {
		return "", err
	}
	return buf.String(), nil
}

func decodeCursor(cursorString string) (Cursor, error) {
	var cursor Cursor
	err := json.NewDecoder(base64.NewDecoder(base64.StdEncoding, strings.NewReader(cursorString))).Decode(&cursor)
	return cursor, err
}

// buildCursor returns the corresponding cursor string for a specific document and set of sort fields
func buildCursor(doc ts.SearchDocument, sortFields []string) (string, error) {
	cursor := Cursor{}
	for _, field := range sortFields {
		switch field {
		case "alert_id":
			cursor.AlertID = &doc.AlertID
		case "weight":
			cursor.Weight = &doc.Weight
		case "updated_at":
			unixMilli := doc.UpdatedAt.UnixMilli()
			cursor.UpdatedAt = &unixMilli
		case "created_at":
			unixMilli := doc.CreatedAt.UnixMilli()
			cursor.CreatedAt = &unixMilli
		default:
			return "", errors.Errorf("Cannot find field: %s", field)
		}
	}
	return EncodeCursor(cursor)
}

// extractCursorFields returns the required values to be used for the `SearchAfter` part of the query, based on
// the encoded cursor string and sort fields.
func extractCursorFields(sortFields []string, encodedCursor string) ([]interface{}, error) {
	cursorFields := []interface{}{}
	if encodedCursor != "" {
		cursor, err := decodeCursor(encodedCursor)
		if err != nil {
			return nil, err
		}

		for _, field := range sortFields {
			var value interface{}

			switch field {
			case "alert_id":
				if cursor.AlertID != nil {
					value = *cursor.AlertID
				}
			case "weight":
				if cursor.Weight != nil {
					value = *cursor.Weight
				}
			case "updated_at":
				if cursor.UpdatedAt != nil {
					value = *cursor.UpdatedAt
				}
			case "created_at":
				if cursor.CreatedAt != nil {
					value = *cursor.CreatedAt
				}
			}

			if value == nil {
				return nil, errors.New("Could not find cursor value for field " + field)
			}

			cursorFields = append(cursorFields, value)
		}
	}
	return cursorFields, nil
}
